extends RefCounted
## Network conditioner, rollback debugger and replay inspector.

const NetConditioner = preload("res://scripts/shared/net_conditioner.gd")
const RollbackNetcode = preload("res://scripts/shared/rollback_netcode.gd")
const RollbackDebugger = preload("res://scripts/shared/rollback_debugger.gd")
const ReplayRecorder = preload("res://scripts/server/replay_recorder.gd")
const ReplayInspector = preload("res://scripts/server/replay_inspector.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


static func _step(state: Dictionary, inputs: Dictionary, _dt: float) -> Dictionary:
	var pos: Dictionary = state["pos"]
	for pid in inputs:
		var inp: Dictionary = inputs[pid]
		pos[pid] = int(pos.get(pid, 0)) + int(inp.get("dx", 0))
	state["pos"] = pos
	return state


static func _bad_step(state: Dictionary, inputs: Dictionary, dt: float) -> Dictionary:
	var s: Dictionary = _step(state, inputs, dt)
	(s["pos"] as Dictionary)[2] = int((s["pos"] as Dictionary).get(2, 0)) + 1
	return s


func _make_net(step: Callable) -> RefCounted:
	var n: RefCounted = RollbackNetcode.new()
	n.setup(step, {"pos": {1: 0, 2: 0}}, [1, 2], [1], 1.0 / 60.0, 0, 8, 0)
	return n


func _make_server(_seed_value: int, _world_seed: int) -> Object:
	var s: Object = GameServer.new(WorldGen.new(1), 1)
	s.craft_quality_enabled = false
	s.zombies.clear()
	return s


func run(t) -> void:
	_test_conditioner(t)
	_test_rollback(t)
	_test_replay(t)


func _test_conditioner(t) -> void:
	t.current = "net conditioner sanitizes invalid diagnostic settings"
	var guard := NetConditioner.new()
	guard.configure({"latency_ms": NAN, "jitter_ms": INF, "loss": NAN,
		"duplicate": INF, "reorder": -INF, "bandwidth_kbps": NAN,
		"max_queue_ms": NAN, "seed": 3})
	t.eq(guard.latency_ms, 0.0, "NaN latency resets to zero")
	t.eq(guard.jitter_ms, 0.0, "infinite jitter is rejected")
	t.eq(guard.loss, 0.0, "invalid packet-loss value is rejected")
	t.eq(guard.duplicate, 0.0, "invalid duplicate ratio is rejected")
	t.eq(guard.reorder, 0.0, "invalid reorder ratio is rejected")
	t.eq(guard.bandwidth_kbps, 0.0, "invalid bandwidth is unlimited")
	t.eq(guard.max_queue_ms, 1000.0, "invalid queue duration uses safe fallback")
	guard.send(0, PackedByteArray([1]), 0.0)
	t.eq(guard.receive(0.0).size(), 1, "packet delivery remains usable")
	t.current = "net conditioner latency/jitter"
	var nc: RefCounted = NetConditioner.new()
	nc.configure({"latency_ms": 100.0, "jitter_ms": 20.0, "seed": 7})
	for i in range(200):
		nc.send(0, PackedByteArray([i % 256]), float(i) * 0.01)
	var lo: float = 1e9
	var hi: float = 0.0
	for e in nc.timeline(0.0, 100.0):
		var d: Dictionary = e
		var ms: float = (float(d["delivered_at"]) - float(d["sent_at"])) * 1000.0
		lo = minf(lo, ms)
		hi = maxf(hi, ms)
	t.check(lo >= 79.99 and hi <= 120.01, "delay stays within latency +/- jitter")
	t.check(hi - lo > 5.0, "jitter actually varies the delay")
	t.eq(nc.receive(0.05).size() < 200, true, "early receive returns only due packets")
	t.eq(nc.receive(1000.0).size() + 0 > 0, true, "late receive drains the rest")

	t.current = "net conditioner loss"
	var lossy: RefCounted = NetConditioner.new()
	lossy.configure({"loss": 0.2, "seed": 3})
	for i in range(2000):
		lossy.send(1, PackedByteArray([1, 2, 3]), 0.0)
	var st: Dictionary = lossy.stats()
	t.near(float(st["dropped"]) / 2000.0, 0.2, 0.04, "loss rate within tolerance")
	t.eq(int(st["dropped"]) + int(st["delivered"]), 2000, "every packet is delivered or dropped")

	t.current = "net conditioner duplicate/reorder"
	var dr: RefCounted = NetConditioner.new()
	dr.configure({"latency_ms": 50.0, "duplicate": 0.2, "reorder": 0.2, "seed": 11})
	for i in range(300):
		dr.send(0, PackedByteArray([i % 256]), float(i) * 0.005)
	var got: Array = dr.receive(100.0)
	var ds: Dictionary = dr.stats()
	t.check(int(ds["duplicated"]) > 0, "duplicates occur")
	t.check(got.size() > 300, "duplicates deliver extra copies")
	t.check(int(ds["reordered"]) > 0, "reordering occurs")
	var inverted: bool = false
	var last_id: int = -1
	var seen: Dictionary = {}
	for g in got:
		var gd: Dictionary = g
		var gid: int = gd["id"]
		if not seen.has(gid):
			if gid < last_id:
				inverted = true
			last_id = maxi(last_id, gid)
			seen[gid] = true
	t.check(inverted, "receive order differs from send order")

	t.current = "net conditioner bandwidth"
	var bw: RefCounted = NetConditioner.new()
	bw.configure({"latency_ms": 10.0, "bandwidth_kbps": 80.0, "max_queue_ms": 150.0, "seed": 1})
	var ids: Array = []
	for i in range(30):
		ids.append(bw.send(0, _bytes(100), 0.0))
	var bst: Dictionary = bw.stats()
	t.check(int(bst["dropped_bandwidth"]) > 0, "queue overflow drops packets")
	var first: Dictionary = bw.packet(ids[0])
	var queued: Dictionary = bw.packet(ids[10])
	t.near(float(queued["queue_ms"]), 100.0, 0.01, "11th packet waits behind 10 others")
	t.check(float(queued["delivered_at"]) > float(first["delivered_at"]), "queued packet arrives later")
	t.check(bw.delay_cause(ids[10]).contains("queued"), "delay_cause names queueing")
	t.check(bw.delay_cause(ids[29]).contains("dropped"), "delay_cause explains drops")
	t.check(bw.delay_cause(ids[0]).contains("base latency"), "delay_cause names base latency")

	t.current = "net conditioner determinism"
	var cfg: Dictionary = {"latency_ms": 60.0, "jitter_ms": 30.0, "loss": 0.1, "duplicate": 0.1,
		"reorder": 0.1, "bandwidth_kbps": 200.0, "seed": 99}
	var a: RefCounted = NetConditioner.new()
	var b: RefCounted = NetConditioner.new()
	a.configure(cfg)
	b.configure(cfg)
	for i in range(100):
		a.send(0, _bytes(50), float(i) * 0.01)
		b.send(0, _bytes(50), float(i) * 0.01)
	t.eq(a.timeline(0.0, 100.0), b.timeline(0.0, 100.0), "same seed gives identical log")
	t.eq(a.stats(), b.stats(), "same seed gives identical stats")
	t.check(float(a.stats()["throughput_bps"]) > 0.0, "throughput reported")


func _bytes(n: int) -> PackedByteArray:
	var p: PackedByteArray = PackedByteArray()
	p.resize(n)
	return p


func _test_rollback(t) -> void:
	t.current = "rollback debugger"
	var net: RefCounted = _make_net(_step)
	var dbg: RefCounted = RollbackDebugger.new(net)
	for i in range(5):
		dbg.add_local_input(1, {"dx": 1})
		dbg.advance()
	t.eq(dbg.rollbacks.size(), 0, "no rollback while predictions hold")
	# Remote player 2 actually moved; prediction (empty) was wrong for frame 1, right for 0.
	dbg.add_remote_input(2, 0, {})
	dbg.add_remote_input(2, 1, {"dx": 3})
	dbg.process()
	t.eq(dbg.rollbacks.size(), 1, "one rollback recorded")
	var r: Dictionary = dbg.rollbacks[0]
	t.eq(int(r["from_frame"]), 1, "rollback starts at the mispredicted frame")
	t.eq(int(r["to_frame"]), 5, "rollback returns to the old head")
	t.eq(int(r["frames_resimulated"]), 4, "frames resimulated counted")
	t.eq(int(r["cause"]), 2, "cause player identified")
	t.near(dbg.miss_rate(2), 0.5, 0.001, "prediction miss rate 1 of 2")
	t.eq(int((net.state["pos"] as Dictionary)[2]), 12, "state corrected after rollback")
	t.check(dbg.report().contains("rollbacks=1"), "report lists rollbacks")

	t.current = "rollback debugger desync"
	var na: RefCounted = _make_net(_step)
	var nb: RefCounted = _make_net(_bad_step)
	var da: RefCounted = RollbackDebugger.new(na)
	var db: RefCounted = RollbackDebugger.new(nb)
	for i in range(4):
		for n in [na, nb]:
			n.add_local_input(1, {"dx": 1})
			n.add_remote_input(2, i, {"dx": 0})
		da.advance()
		db.advance()
	for rep in db.net.get_checksum_report():
		var e: Dictionary = rep
		na.add_remote_checksum(int(e["frame"]), int(e["checksum"]))
	t.check(na.has_desync(), "netcode detects checksum mismatch")
	t.check(da.desyncs.size() > 0, "debugger records the desync")
	if da.desyncs.size() > 0:
		var fr: int = da.desyncs[0]["frame"]
		var remote: Dictionary = db.state_history(fr)
		var diff: Array = da.attach_remote_state(fr, remote)
		t.check(diff.has("pos.2"), "diff names the diverged key path ")
		t.check(not diff.has("pos.1"), "diff leaves matching keys out")
	t.eq(RollbackDebugger.diff_states({"a": {"b": 1, "c": [1, 2]}}, {"a": {"b": 2, "c": [1, 3]}, "d": 1}),
		["a.b", "a.c[1]", "d"], "diff_states reports nested paths")
	t.check(da.report().contains("DESYNC"), "report lists desyncs")


func _test_replay(t) -> void:
	t.current = "replay inspector"
	var rec: ReplayRecorder = ReplayRecorder.new(1, 1)
	rec.add_initial_player(1, "Ann")
	var live: Object = _make_server(1, 1)
	live.add_player(1, "Ann")
	var hashes: Array = []
	for i in range(6):
		if i < 4:
			rec.record_command(1, "submit_input", [i + 1, 1.0, 0.0, false, 0.0, 0.1, false])
			live.submit_input(1, i + 1, 1.0, 0.0, false, 0.0, 0.1, false)
		if i == 2:
			rec.record_command(1, "cmd_survey_ruins", [])
			live.cmd_survey_ruins(1)
		rec.end_tick(0.1)
		live.tick(0.1)
		hashes.append(ReplayRecorder.state_hash(live))
	var path: String = "user://net_debug_test.replay"
	t.check(rec.save(path), "replay saved")
	var insp: RefCounted = ReplayInspector.new()
	t.check(insp.load_file(path), "inspector loads replay")
	var sm: Dictionary = insp.summary()
	t.eq(int(sm["ticks"]), 6, "summary tick count")
	t.eq(sm["players"], [1], "summary players")
	t.eq(int((sm["commands_by_type"] as Dictionary)["submit_input"]), 4, "summary counts movement")
	t.eq(int((sm["commands_by_type"] as Dictionary)["cmd_survey_ruins"]), 1, "summary counts commands")
	t.eq(insp.list_ticks(true).size(), 4, "list ticks with commands")
	var s3: Dictionary = insp.state_at(3, _make_server)
	t.eq(int(s3["tick"]), 3, "state_at reaches the requested tick")
	t.eq(int(s3["hash"]), int(hashes[3]), "state_at hash matches the live run")
	var s5: Dictionary = insp.state_at(5, _make_server)
	t.check((s5["players"][1]["pos"] as Vector3).x > (s3["players"][1]["pos"] as Vector3).x - 0.0001, "later state is at or beyond earlier x")
	t.eq(insp.find_first_divergence(insp.replay, _make_server, hashes)["tick"], -1, "no divergence from faithful hashes")
	var bad: Array = hashes.duplicate()
	bad[4] = int(bad[4]) + 1
	var dv: Dictionary = insp.find_first_divergence(insp.replay, _make_server, bad)
	t.eq(int(dv["tick"]), 4, "first divergence located")
	var dh: Dictionary = ReplayInspector.diff_hashes(hashes, bad)
	t.eq(int(dh["first"]), 4, "diff_hashes first tick")
	t.eq(dh["differing"], [4], "diff_hashes lists differing ticks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
