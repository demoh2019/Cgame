extends RefCounted
## Two-phase-commit coordinator with a durable decision log, plus a persistent order book.
##
## Original GDScript implementation. Design references (concepts only, no code copied):
##   - Gray & Lamport, "Consensus on Transaction Commit" / classic 2PC with presumed abort
##     (Mohan, Lindsay, Obermarck, "Transaction Management in the R* Distributed DBMS").
##   - Atomic write via temp file + rename (the standard POSIX durable-update idiom).
## License of this file: same as the project; no third-party code included.
##
## Protocol: begin() logs the intent and ops. run() asks every participant to prepare; if all
## say yes the COMMIT decision is logged durably, otherwise ABORT. The decision is then delivered
## to each participant; per-participant acks are logged so a restart never re-sends a finished
## commit. recover() re-drives unfinished transactions: a logged decision is re-delivered
## (participants must treat commit/abort as idempotent), no decision means presumed abort.

var store_path: String = ""        ## "" = in-memory only
var prepare_timeout_msec: int = 0  ## 0 = no timeout; a slower prepare counts as a refusal
var crash_point: String = ""       ## test hook: "before_decision" | "after_decision"
var crashed: bool = false

var txs: Dictionary = {}                 ## tx_id -> record
var persistent_orders: Dictionary = {}   ## order_id(String) -> order record
var _next_tx: int = 1
var _next_order: int = 1
var _participants: Dictionary = {}       ## name -> {prepare, commit, abort}


func add_participant(pname: String, prepare: Callable, commit: Callable, abort: Callable) -> void:
	_participants[pname] = {"prepare": prepare, "commit": commit, "abort": abort}


func set_path(path: String) -> void:
	store_path = path


## Loads the store (if any). Safe on missing/corrupt files (starts empty).
func load_store() -> bool:
	if store_path == "" or not FileAccess.file_exists(store_path):
		return false
	var f := FileAccess.open(store_path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	txs = d.get("txs", {})
	persistent_orders = d.get("orders", {})
	_next_tx = int(d.get("next_tx", 1))
	_next_order = int(d.get("next_order", 1))
	return true


func save_store() -> bool:
	if store_path == "":
		return true
	var tmp := store_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"txs": txs, "orders": persistent_orders,
		"next_tx": _next_tx, "next_order": _next_order}))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(store_path))
	return err == OK


# ---------------------------------------------------------------- transactions

func begin(ops_by_participant: Dictionary) -> String:
	var id := "tx%d" % _next_tx
	_next_tx += 1
	txs[id] = {"state": "begun", "ops": ops_by_participant.duplicate(true), "decision": "",
		"acked": [], "started": Time.get_unix_time_from_system()}
	save_store()
	return id


func status(tx_id: String) -> String:
	if not txs.has(tx_id):
		return "unknown"
	var tx: Dictionary = txs[tx_id]
	return String(tx["state"])


## Drives a transaction to completion. Returns "committed", "aborted" or "crashed" (test hook).
func run(tx_id: String) -> String:
	if crashed:
		return "crashed"
	if not txs.has(tx_id):
		return "aborted"  # presumed abort
	var tx: Dictionary = txs[tx_id]
	if String(tx["decision"]) == "":
		var ops: Dictionary = tx["ops"]
		var ok := true
		for pname in ops.keys():
			var key := String(pname)
			if not _participants.has(key):
				ok = false
				break
			var p: Dictionary = _participants[key]
			var prep: Callable = p["prepare"]
			var t0 := Time.get_ticks_msec()
			var vote: Variant = prep.call(tx_id, ops[pname])
			var slow := prepare_timeout_msec > 0 and Time.get_ticks_msec() - t0 > prepare_timeout_msec
			if vote != true or slow:
				ok = false
				break
		if crash_point == "before_decision":
			crashed = true
			return "crashed"
		tx["decision"] = "commit" if ok else "abort"
		tx["state"] = "decided"
		save_store()
		if crash_point == "after_decision":
			crashed = true
			return "crashed"
	return _deliver(tx_id)


func _deliver(tx_id: String) -> String:
	var tx: Dictionary = txs[tx_id]
	var decision := String(tx["decision"])
	var acked: Array = tx["acked"]
	var ops: Dictionary = tx["ops"]
	for pname in ops.keys():
		var key := String(pname)
		if acked.has(key) or not _participants.has(key):
			continue
		var p: Dictionary = _participants[key]
		var cb: Callable = p["commit"] if decision == "commit" else p["abort"]
		cb.call(tx_id)
		acked.append(key)
		save_store()
	if acked.size() >= ops.size():
		tx["state"] = "done"
		save_store()
	return "committed" if decision == "commit" else "aborted"


## After a restart (new instance, load_store(), participants re-added): finish in-doubt txs.
func recover() -> Dictionary:
	crashed = false
	crash_point = ""
	var results := {}
	for id in txs.keys():
		var tx: Dictionary = txs[id]
		if String(tx["state"]) == "done":
			continue
		if String(tx["decision"]) == "":
			tx["decision"] = "abort"  # presumed abort: no commit decision was logged
			tx["state"] = "decided"
			save_store()
		results[id] = _deliver(String(id))
	return results


## Aborts undecided transactions older than max_age_sec.
func abort_stale(now_unix: float, max_age_sec: float) -> int:
	var n := 0
	for id in txs.keys():
		var tx: Dictionary = txs[id]
		if String(tx["decision"]) == "" and now_unix - float(tx["started"]) > max_age_sec:
			tx["decision"] = "abort"
			tx["state"] = "decided"
			_deliver(String(id))
			n += 1
	return n


# ------------------------------------------------------------ persistent order book

## side: "buy" | "sell". Returns order id.
func place_order(owner: String, side: String, item: String, price: float, qty: int) -> String:
	var id := str(_next_order)
	persistent_orders[id] = {"id": id, "seq": _next_order, "owner": owner, "side": side,
		"item": item, "price": price, "qty": qty}
	_next_order += 1
	save_store()
	return id


func cancel_order(order_id: String) -> bool:
	if not persistent_orders.has(order_id):
		return false
	persistent_orders.erase(order_id)
	save_store()
	return true


func open_orders(item: String, side: String) -> Array:
	var out: Array = []
	for id in persistent_orders.keys():
		var o: Dictionary = persistent_orders[id]
		if o["item"] == item and o["side"] == side:
			out.append(o)
	if side == "buy":
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["price"]) != float(b["price"]):
				return float(a["price"]) > float(b["price"])
			return int(a["seq"]) < int(b["seq"]))
	else:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["price"]) != float(b["price"]):
				return float(a["price"]) < float(b["price"])
			return int(a["seq"]) < int(b["seq"]))
	return out


## Price-time priority matching; trades execute at the resting (older) order's price.
## Returns [{buyer, seller, item, price, qty, buy_id, sell_id}].
func match_orders(item: String) -> Array:
	var trades: Array = []
	while true:
		var buys := open_orders(item, "buy")
		var sells := open_orders(item, "sell")
		if buys.is_empty() or sells.is_empty():
			break
		var b: Dictionary = buys[0]
		var s: Dictionary = sells[0]
		if float(b["price"]) < float(s["price"]):
			break
		var qty := mini(int(b["qty"]), int(s["qty"]))
		var price: float = float(b["price"]) if int(b["seq"]) < int(s["seq"]) else float(s["price"])
		trades.append({"buyer": b["owner"], "seller": s["owner"], "item": item, "price": price,
			"qty": qty, "buy_id": b["id"], "sell_id": s["id"]})
		b["qty"] = int(b["qty"]) - qty
		s["qty"] = int(s["qty"]) - qty
		if int(b["qty"]) <= 0:
			persistent_orders.erase(String(b["id"]))
		if int(s["qty"]) <= 0:
			persistent_orders.erase(String(s["id"]))
	if not trades.is_empty():
		save_store()
	return trades
