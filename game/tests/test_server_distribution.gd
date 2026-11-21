extends RefCounted
## Two-phase commit coordinator, persistent order book and world sharding / handoff.

const Coordinator = preload("res://scripts/server/transaction_coordinator.gd")
const Sharding = preload("res://scripts/server/world_sharding.gd")

const STORE := "user://test_tx_store.json"

var _log: Dictionary = {}


func _cleanup() -> void:
	for p in [STORE, STORE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _bump(key: String) -> void:
	_log[key] = int(_log.get(key, 0)) + 1


func _count(key: String) -> int:
	return int(_log.get(key, 0))


func _wire(c, refuse: String = "") -> void:
	for pname in ["a", "b"]:
		var n: String = pname
		c.add_participant(n,
			func(_tx: String, _ops: Variant) -> bool: return n != refuse,
			func(_tx: String) -> void: _bump("commit_" + n),
			func(_tx: String) -> void: _bump("abort_" + n))


func run(t) -> void:
	_cleanup()
	t.current = "2pc basic"
	_log.clear()
	var c = Coordinator.new()
	_wire(c)
	var id: String = c.begin({"a": {"gold": -5}, "b": {"item": 1}})
	t.eq(c.run(id), "committed", "commits when all prepare")
	t.eq(_count("commit_a") + _count("commit_b"), 2, "both participants committed")
	t.eq(c.run(id), "committed", "re-run is idempotent")
	t.eq(_count("commit_a"), 1, "commit delivered once")
	t.eq(c.run("nope"), "aborted", "unknown tx presumed aborted")

	_log.clear()
	var c2 = Coordinator.new()
	_wire(c2, "b")
	var id2: String = c2.begin({"a": 1, "b": 2})
	t.eq(c2.run(id2), "aborted", "aborts when one refuses")
	t.eq(_count("commit_a") + _count("commit_b"), 0, "nobody committed on abort")
	t.eq(_count("abort_a"), 1, "abort reaches the prepared participant")

	t.current = "2pc crash recovery"
	_log.clear()
	var c3 = Coordinator.new()
	c3.set_path(STORE)
	_wire(c3)
	c3.crash_point = "after_decision"
	var id3: String = c3.begin({"a": 1, "b": 2})
	t.eq(c3.run(id3), "crashed", "crash hook fires after decision")
	t.eq(_count("commit_a"), 0, "nothing delivered before crash")
	var r3 = Coordinator.new()
	r3.set_path(STORE)
	t.check(r3.load_store(), "log reloads from disk")
	_wire(r3)
	var res: Dictionary = r3.recover()
	t.eq(res.get(id3, ""), "committed", "recover re-drives committed decision")
	t.eq(_count("commit_a"), 1, "commit delivered exactly once to a")
	t.eq(_count("commit_b"), 1, "commit delivered exactly once to b")
	var res_again: Dictionary = r3.recover()
	t.check(res_again.is_empty(), "finished tx not re-driven")
	t.eq(_count("commit_a"), 1, "still exactly once after second recover")

	_log.clear()
	var c4 = Coordinator.new()
	c4.set_path(STORE)
	c4.load_store()
	_wire(c4)
	c4.crash_point = "before_decision"
	var id4: String = c4.begin({"a": 1, "b": 2})
	t.eq(c4.run(id4), "crashed", "crash before decision")
	var r4 = Coordinator.new()
	r4.set_path(STORE)
	r4.load_store()
	_wire(r4)
	var res4: Dictionary = r4.recover()
	t.eq(res4.get(id4, ""), "aborted", "undecided tx recovers to abort")
	t.eq(_count("commit_a") + _count("commit_b"), 0, "no commit after presumed abort")
	t.eq(r4.status(id4), "done", "recovered tx finished")

	t.current = "persistent orders"
	var ob = Coordinator.new()
	ob.set_path(STORE)
	ob.load_store()
	var sell1: String = ob.place_order("alice", "sell", "wood", 10.0, 5)
	var buy1: String = ob.place_order("bob", "buy", "wood", 8.0, 3)
	t.eq(ob.match_orders("wood").size(), 0, "no match below ask")
	var buy2: String = ob.place_order("carol", "buy", "wood", 12.0, 4)
	var restarted = Coordinator.new()
	restarted.set_path(STORE)
	t.check(restarted.load_store(), "orders reload")
	t.eq(restarted.persistent_orders.size(), 3, "orders survive restart")
	var trades: Array = restarted.match_orders("wood")
	t.eq(trades.size(), 1, "one trade matched")
	var tr: Dictionary = trades[0]
	t.eq(tr["buyer"], "carol", "highest bid wins")
	t.eq(int(tr["qty"]), 4, "fills bid quantity")
	t.near(float(tr["price"]), 10.0, 0.001, "executes at resting ask")
	var left: Array = restarted.open_orders("wood", "sell")
	var rem: Dictionary = left[0]
	t.eq(int(rem["qty"]), 1, "partial fill leaves remainder")
	t.check(restarted.cancel_order(buy1), "cancel works")
	t.check(not restarted.cancel_order(buy1), "double cancel is false")
	t.check(sell1 != buy2, "distinct order ids")
	_cleanup()

	t.current = "sharding assignment"
	var w = Sharding.new()
	w.setup(4, 4, 100.0, 4)
	var loads: Array = []
	for i in 16:
		loads.append(float(10 + (i % 4) * 5))
	w.assign_initial(loads)
	var sl: Array = w.server_loads(loads)
	var mx: float = sl.max()
	var mn: float = sl.min()
	t.check(mx <= mn * 1.2, "regions balanced across servers")
	var counts := {}
	for r in 16:
		var s: int = w.region_owner[r]
		counts[s] = int(counts.get(s, 0)) + 1
	t.eq(counts.size(), 4, "every server owns regions")

	t.current = "sharding rebalance"
	var calm: Array = loads.duplicate()
	t.eq(w.rebalance(calm).size(), 0, "balanced world does not move regions")
	var hot: Array = loads.duplicate()
	for r in 16:
		if w.region_owner[r] == 0:
			hot[r] = float(hot[r]) * 4.0
	var moves: Array = w.rebalance(hot)
	t.check(moves.size() > 0, "overloaded server sheds regions")
	var m0: Dictionary = moves[0]
	t.eq(int(m0["from"]), 0, "moves leave the hot server")
	t.eq(w.rebalance(hot).size(), 0, "second rebalance does not thrash")
	var nudged: Array = hot.duplicate()
	nudged[0] = float(nudged[0]) * 1.02
	t.eq(w.rebalance(nudged).size(), 0, "small load noise inside hysteresis band")

	t.current = "handoff"
	var h = Sharding.new()
	h.setup(2, 1, 100.0, 2)
	h.region_owner[0] = 0
	h.region_owner[1] = 1
	t.eq(h.handoff_needed(Vector2(50, 50), 0), -1, "interior needs no handoff")
	t.eq(h.handoff_needed(Vector2(99.0, 50), 0), -1, "hysteresis near border")
	t.eq(h.handoff_needed(Vector2(150, 50), 0), 1, "crossing border triggers handoff")
	t.eq(h.ghost_servers(Vector2(90, 50), 0), [1], "ghost on neighbour within margin")
	t.eq(h.ghost_servers(Vector2(30, 50), 0), [], "no ghost far from border")
	h.track_player("p1", Vector2(90, 50), 0)
	var upd: Dictionary = h.update_player("p1", Vector2(150, 50))
	t.eq(int(upd["handoff_to"]), 1, "update reports handoff target")
	var tid: String = h.begin_transfer("p1", 1, "t-1")
	t.eq(tid, "t-1", "transfer begins")
	var pl: Dictionary = h.players["p1"]
	t.eq(pl["state"], "frozen", "player frozen")
	t.eq(h.begin_transfer("p1", 1, "t-2"), "", "second transfer while frozen rejected")
	t.eq(h.begin_transfer("p1", 1, "t-1"), "t-1", "duplicate transfer id ignored")
	t.check(not h.release_transfer("t-1"), "cannot release before ack")
	t.check(h.send_state("t-1", {"hp": 80}), "state sent")
	t.check(h.ack_transfer("t-1"), "destination acks")
	t.check(h.release_transfer("t-1"), "source releases")
	t.eq(h.owner_of("p1"), 1, "ownership flipped")
	t.eq(pl["state"], "stable", "player stable on new owner")
	t.eq(h.begin_transfer("p1", 1, "t-1"), "t-1", "replayed id after completion ignored")
	t.eq(h.owner_of("p1"), 1, "replay does not change owner")
	t.check(h.release_transfer("t-1"), "release idempotent")
	var tid2: String = h.begin_transfer("p1", 0, "t-3")
	t.check(h.abort_transfer(tid2), "abort unfinished transfer")
	t.eq(h.owner_of("p1"), 1, "aborted transfer keeps source owner")
	t.eq(h.entities_on(1), ["p1"], "entity table lists owned entities")
