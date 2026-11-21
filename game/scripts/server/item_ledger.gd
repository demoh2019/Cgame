extends RefCounted
## Per-server item ownership ledger: globally unique item instance ids, exactly-once cross-server
## moves as a two-phase-commit participant, and duplicate detection with quarantine.
##
## Original GDScript implementation. Concept references only (no code copied):
##   - Gray & Lamport, "Consensus on Transaction Commit" (2PC participant: prepare / commit / abort,
##     all idempotent so a re-delivered decision is harmless).
##   - Unique ids = (server id, local counter) composite keys, the usual snowflake-style scheme.
##   - Idempotent receiver: remember applied transaction ids (exactly-once effect over at-least-once
##     delivery), see Kleppmann, "Designing Data-Intensive Applications", ch. 11-12.
## License of this file: same as the project; no third-party code included.
##
## States: "active" (usable), "locked" (prepared for an outgoing move, unusable), "quarantined"
## (suspected duplicate, frozen until an operator/resolve_duplicate decides).
## Wire it to TransactionCoordinator with prepare()/commit()/abort() (tx_id first argument).

var server_id: int = 0
var items: Dictionary = {}        ## item id -> {id, owner, def, epoch, state, lock_tx}
var pending: Dictionary = {}      ## tx id -> {kind: "out"|"in", ids: Array, recs: Array}
var applied: Dictionary = {}      ## tx id -> "commit" | "abort" (idempotence memory)
var quarantine: Dictionary = {}   ## item id -> reason
var _counter: int = 0


func _init(p_server_id: int = 0) -> void:
	server_id = p_server_id


## Mints a brand-new item with a globally unique id ("i<server>-<n>").
func mint(owner: String, def: String) -> String:
	_counter += 1
	var id := "i%d-%d" % [server_id, _counter]
	items[id] = {"id": id, "owner": owner, "def": def, "epoch": 0, "state": "active", "lock_tx": ""}
	return id


func has_item(id: String) -> bool:
	return items.has(id)


func state_of(id: String) -> String:
	if not items.has(id):
		return ""
	var it: Dictionary = items[id]
	return String(it["state"])


func is_active(id: String) -> bool:
	return state_of(id) == "active"


func owner_of(id: String) -> String:
	if not items.has(id):
		return ""
	var it: Dictionary = items[id]
	return String(it["owner"])


func epoch_of(id: String) -> int:
	if not items.has(id):
		return -1
	var it: Dictionary = items[id]
	return int(it["epoch"])


func total_count() -> int:
	return items.size()


func active_count() -> int:
	var n := 0
	for id in items.keys():
		if is_active(String(id)):
			n += 1
	return n


func ids_sorted() -> Array:
	var ids: Array = items.keys()
	ids.sort()
	return ids


## Active item ids owned by `owner`, sorted.
func items_of(owner: String) -> Array:
	var out: Array = []
	for id in ids_sorted():
		var it: Dictionary = items[id]
		if String(it["owner"]) == owner and String(it["state"]) == "active":
			out.append(id)
	return out


func snapshot(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if items.has(id):
			var it: Dictionary = items[id]
			out.append(it.duplicate(true))
	return out


# ------------------------------------------------------------------ 2PC participant

## op: {"kind": "out", "ids": [...]} on the source, {"kind": "in", "recs": [...]} on the target.
## Returns the vote. Re-preparing the same tx is idempotent.
func prepare(tx_id: String, op: Variant) -> bool:
	if typeof(op) != TYPE_DICTIONARY:
		return false
	if applied.has(tx_id):
		return String(applied[tx_id]) == "commit"
	if pending.has(tx_id):
		return true
	var d: Dictionary = op
	var kind := String(d.get("kind", ""))
	if kind == "out":
		var ids: Array = d.get("ids", [])
		for id in ids:
			if not is_active(String(id)):
				return false  # missing, locked by another tx, or quarantined
		for id in ids:
			var it: Dictionary = items[String(id)]
			it["state"] = "locked"
			it["lock_tx"] = tx_id
		pending[tx_id] = {"kind": "out", "ids": ids.duplicate(), "recs": []}
		return true
	if kind == "in":
		var recs: Array = d.get("recs", [])
		var seen := {}
		for r in recs:
			var rec: Dictionary = r
			var rid := String(rec["id"])
			if items.has(rid) or seen.has(rid):
				return false  # we already hold this id: refuse instead of duplicating
			seen[rid] = true
		pending[tx_id] = {"kind": "in", "ids": seen.keys(), "recs": recs.duplicate(true)}
		return true
	return false


func commit(tx_id: String) -> void:
	if applied.has(tx_id):
		return
	applied[tx_id] = "commit"
	if not pending.has(tx_id):
		return
	var p: Dictionary = pending[tx_id]
	pending.erase(tx_id)
	if String(p["kind"]) == "out":
		for id in p["ids"]:
			items.erase(String(id))
	else:
		for r in p["recs"]:
			var rec: Dictionary = r
			var rid := String(rec["id"])
			var incoming := {"id": rid, "owner": String(rec["owner"]), "def": String(rec["def"]),
				"epoch": int(rec["epoch"]) + 1, "state": "active", "lock_tx": ""}
			if items.has(rid):
				# Should be impossible (prepare refuses): freeze the existing copy for review.
				quarantine_item(rid, "duplicate received in tx " + tx_id)
			else:
				items[rid] = incoming


func abort(tx_id: String) -> void:
	if applied.has(tx_id):
		return
	applied[tx_id] = "abort"
	if not pending.has(tx_id):
		return
	var p: Dictionary = pending[tx_id]
	pending.erase(tx_id)
	if String(p["kind"]) == "out":
		for id in p["ids"]:
			var key := String(id)
			if items.has(key):
				var it: Dictionary = items[key]
				if String(it["state"]) == "locked" and String(it["lock_tx"]) == tx_id:
					it["state"] = "active"
					it["lock_tx"] = ""


# ------------------------------------------------------------------ duplicate handling

func quarantine_item(id: String, reason: String) -> void:
	if not items.has(id):
		return
	var it: Dictionary = items[id]
	it["state"] = "quarantined"
	it["lock_tx"] = ""
	quarantine[id] = reason


## ledgers: Array of ItemLedger. Returns {item id -> [server ids holding it]} for every id held by
## more than one ledger (any state).
static func find_duplicates(ledgers: Array) -> Dictionary:
	var where := {}
	for l in ledgers:
		var led = l
		for id in led.items.keys():
			var key := String(id)
			if not where.has(key):
				where[key] = []
			var arr: Array = where[key]
			arr.append(int(led.server_id))
	var dups := {}
	for id in where.keys():
		var arr: Array = where[id]
		if arr.size() > 1:
			dups[id] = arr
	return dups


## Freezes every copy of every duplicated id. Returns the sorted list of quarantined ids.
static func quarantine_duplicates(ledgers: Array) -> Array:
	var dups := find_duplicates(ledgers)
	for id in dups.keys():
		for l in ledgers:
			var led = l
			if led.items.has(id):
				led.quarantine_item(String(id), "duplicate across servers")
	var out: Array = dups.keys()
	out.sort()
	return out


## Operator/auto resolution: keep the copy with the highest epoch (ties: lowest server id) as
## active, delete the rest. Returns the surviving server id, or -1 if the id is unknown.
static func resolve_duplicate(ledgers: Array, id: String) -> int:
	var best = null
	for l in ledgers:
		var led = l
		if not led.items.has(id):
			continue
		if best == null or led.epoch_of(id) > best.epoch_of(id) \
				or (led.epoch_of(id) == best.epoch_of(id) and led.server_id < best.server_id):
			best = led
	if best == null:
		return -1
	for l in ledgers:
		var led = l
		if led != best and led.items.has(id):
			led.items.erase(id)
			led.quarantine.erase(id)
	var it: Dictionary = best.items[id]
	it["state"] = "active"
	best.quarantine.erase(id)
	return int(best.server_id)


# ------------------------------------------------------------------ persistence

func to_dict() -> Dictionary:
	return {"server_id": server_id, "items": items.duplicate(true), "pending": pending.duplicate(true),
		"applied": applied.duplicate(), "quarantine": quarantine.duplicate(), "counter": _counter}


func from_dict(d: Dictionary) -> void:
	server_id = int(d.get("server_id", 0))
	items = d.get("items", {})
	pending = d.get("pending", {})
	applied = d.get("applied", {})
	quarantine = d.get("quarantine", {})
	_counter = int(d.get("counter", 0))
