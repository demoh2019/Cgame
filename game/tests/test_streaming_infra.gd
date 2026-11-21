extends RefCounted
## Floating origin, stream request queue, readiness gate and streaming-state replication.

const OriginRebasing = preload("res://scripts/shared/origin_rebasing.gd")
const StreamRequests = preload("res://scripts/shared/stream_requests.gd")
const StreamReadiness = preload("res://scripts/shared/stream_readiness.gd")
const StreamStateReplication = preload("res://scripts/shared/stream_state_replication.gd")

var _hits: int = 0


func _on_shift(_s: Vector3) -> void:
	_hits += 1


func run(t) -> void:
	_origin(t)
	_requests(t)
	_readiness(t)
	_replication(t)


func _origin(t) -> void:
	t.current = "origin rebasing"
	var o := OriginRebasing.new()
	o.threshold = 1000.0
	o.grid_step = 256.0
	o.horizontal_only = true
	t.eq(o.check(Vector3(500, 40, 300)), Vector3.ZERO, "inside threshold: no shift")
	var s := o.check(Vector3(1500, 90, -1300))
	t.check(s != Vector3.ZERO, "outside threshold shifts")
	t.near(fposmod(s.x, 256.0), 0.0, 0.0001, "x shift is a grid multiple")
	t.near(fposmod(s.z, 256.0), 0.0, 0.0001, "z shift is a grid multiple")
	t.eq(s.y, 0.0, "horizontal_only keeps Y")

	var root := Node3D.new()
	var a := Node3D.new()
	a.position = Vector3(1500, 5, -1300)
	var keep := Node3D.new()
	keep.position = Vector3(1, 2, 3)
	keep.add_to_group(OriginRebasing.EXCLUDE_GROUP)
	var not_3d := Node.new()
	root.add_child(a)
	root.add_child(keep)
	root.add_child(not_3d)
	o.add_listener(_on_shift)
	t.eq(o.apply(root, s), 1, "only the non-excluded Node3D moved")
	t.eq(_hits, 1, "listener notified")
	t.eq(keep.position, Vector3(1, 2, 3), "excluded node untouched")
	t.check(a.position.length() < 300.0, "node pulled near origin")
	t.eq(o.to_global_world(a.position), Vector3(1500, 5, -1300), "global position preserved")
	t.eq(o.to_local_world(Vector3(1500, 5, -1300)), a.position, "local conversion inverts")
	t.eq(o.apply(root, Vector3.ZERO), 0, "zero shift is a no-op")
	o.remove_listener(_on_shift)
	root.free()

	# 5000 rebases walking 1000 m along +x: no drift in the exact representation.
	var o2 := OriginRebasing.new()
	o2.threshold = 1500.0
	o2.grid_step = 512.0
	var cam := Vector3(0.5, 1.0, 0.25)
	for i in 5000:
		cam.x += 1000.0
		var sh := o2.check(cam)
		if sh != Vector3.ZERO:
			cam += sh
			o2.commit(sh)
	var g := o2.to_global_split(cam)
	var gc: Vector3i = g["cell"]
	var gr: Vector3 = g["rem"]
	t.near(float(gc.x) * 512.0 + gr.x, 5000000.5, 0.001, "global x exact after many shifts")
	t.near(float(gc.z) * 512.0 + gr.z, 0.25, 0.001, "global z unchanged")
	t.check(absf(cam.x) < 2600.0, "local camera stays small")
	t.check(o2.shift_count > 1000, "many rebases happened")
	t.eq(o2.from_global_split(gc, gr), cam, "split round trip")
	t.near(o2.noise_offset(128.0).x, 0.0, 0.0001, "noise offset zero for periods dividing the step")


func _requests(t) -> void:
	t.current = "stream requests"
	var q := StreamRequests.new()
	q.request(Vector2i(0, 0), 1.0, 1)
	q.request(Vector2i(1, 0), 5.0, 1)
	q.request(Vector2i(2, 0), 3.0, 1)
	q.request(Vector2i(3, 0), 5.0, 1)
	var b := q.next_batch(3)
	t.eq(b, [Vector2i(1, 0), Vector2i(3, 0), Vector2i(2, 0)], "priority then FIFO order")
	t.eq(q.next_batch(5), [Vector2i(0, 0)], "remaining queued cell")
	t.eq(q.next_batch(5).size(), 0, "nothing left")

	var q2 := StreamRequests.new()
	q2.request(Vector2i(0, 0), 1.0, 1)
	q2.request(Vector2i(1, 0), 1.0, 1)
	q2.request(Vector2i(2, 0), 1.0, 1)
	q2.next_batch(1)  # (0,0) in flight
	var n := q2.cancel_stale(2, [Vector2i(1, 0)])
	t.eq(n, 2, "in-flight (0,0) and queued (2,0) cancelled; kept cell survives")
	t.check(not q2.has_request(Vector2i(2, 0)), "queued stale request removed")
	t.eq(q2.state_of(Vector2i(0, 0)), StreamRequests.State.CANCELLED, "in-flight flagged")
	t.check(not q2.complete(Vector2i(0, 0), "late"), "late result of cancelled request dropped")
	t.eq(q2.take_completed().size(), 0, "nothing delivered")
	t.check(not q2.request(Vector2i(9, 9), 1.0, 1), "older generation rejected")
	t.eq(q2.next_batch(4), [Vector2i(1, 0)], "kept cell still loadable")
	t.check(q2.complete(Vector2i(1, 0), "ok"), "kept cell completes")
	var done := q2.take_completed()
	t.eq(done.size(), 1, "one delivered result")
	t.eq(done[0]["result"], "ok", "result payload kept")
	var st := q2.stats()
	t.eq(st["dropped_late"], 1, "stats: dropped late")
	t.eq(st["cancelled_queued"], 1, "stats: cancelled queued")
	t.eq(st["cancelled_inflight"], 1, "stats: cancelled in flight")
	t.eq(st["completed"], 1, "stats: completed")

	var q3 := StreamRequests.new()
	q3.max_in_flight = 2
	for i in 5:
		q3.request(Vector2i(i, 0), float(i), 1)
	t.eq(q3.next_batch(10).size(), 2, "in-flight cap limits batch")
	t.eq(q3.next_batch(10).size(), 0, "cap reached")
	q3.request(Vector2i(4, 0), 0.0, 2)
	t.check(q3.complete(Vector2i(4, 0), 1), "re-request at newer generation revives a live request")
	q3.request(Vector2i(0, 0), 1.0, 3)
	t.check(not q3.complete(Vector2i(4, 0), 1), "second completion of the same cell ignored")


func _readiness(t) -> void:
	t.current = "stream readiness"
	var r := StreamReadiness.new()
	var c := Vector2i(4, 4)
	r.begin(c, 0.0)
	r.mark(c, StreamReadiness.Stage.NAVMESH_READY)
	t.check(not r.is_revealable(c), "navmesh alone not enough")
	t.eq(r.waiting_stage(c), StreamReadiness.Stage.DATA_LOADED, "waiting on data first")
	t.eq(r.ready_mask(c), 0, "early navmesh mark does not count yet")
	r.mark(c, StreamReadiness.Stage.DATA_LOADED)
	t.eq(r.waiting_stage(c), StreamReadiness.Stage.GPU_UPLOADED, "then GPU")
	t.check(not r.is_stage_ready(c, StreamReadiness.Stage.NAVMESH_READY), "navmesh needs physics")
	r.mark(c, StreamReadiness.Stage.GPU_UPLOADED)
	r.mark(c, StreamReadiness.Stage.PHYSICS_READY)
	t.check(r.is_revealable(c), "all stages: revealable (early navmesh mark now counts)")
	t.eq(r.update(1.0), [c], "update reports the reveal once")
	t.eq(r.update(2.0).size(), 0, "no second reveal")
	t.check(r.is_revealed(c), "revealed flag")

	# probes + timeouts
	var r2 := StreamReadiness.new()
	r2.default_timeout = 5.0
	r2.stage_timeouts = {StreamReadiness.Stage.GPU_UPLOADED: 2.0}
	var flags := {"gpu": false}
	r2.set_probe(StreamReadiness.Stage.DATA_LOADED, func(_c: Vector2i) -> bool: return true)
	r2.set_probe(StreamReadiness.Stage.GPU_UPLOADED, func(_c: Vector2i) -> bool: return bool(flags["gpu"]))
	r2.set_probe(StreamReadiness.Stage.PHYSICS_READY, func(_c: Vector2i) -> bool: return true)
	r2.set_probe(StreamReadiness.Stage.NAVMESH_READY, func(_c: Vector2i) -> bool: return true)
	var d := Vector2i(1, 1)
	r2.begin(d, 0.0)
	t.eq(r2.update(0.5).size(), 0, "GPU probe false: not revealable")
	t.eq(r2.stuck_log.size(), 0, "not stuck yet")
	r2.update(2.6)
	t.eq(r2.stuck_log.size(), 1, "stuck reported after the GPU timeout")
	t.eq(r2.stuck_log[0]["stage_name"], "gpu_uploaded", "stuck stage named")
	t.eq(r2.stuck_log[0]["cell"], d, "stuck cell named")
	r2.update(9.0)
	t.eq(r2.stuck_log.size(), 1, "stuck reported only once")
	flags["gpu"] = true
	t.eq(r2.update(10.0), [d], "probes complete the cell once GPU ready")
	t.check(StreamReadiness.probe_rids_valid([]) == false, "empty rid list is not ready")
	t.check(not StreamReadiness.probe_rids_valid([RID()]), "invalid rid is not ready")

	# navmesh warmup budget + auto warmup
	var r3 := StreamReadiness.new()
	var baked: Array[Vector2i] = []
	var bake := func(cell: Vector2i) -> bool:
		baked.append(cell)
		return true
	for i in 5:
		var cell := Vector2i(i, 0)
		r3.begin(cell, 0.0)
		r3.warmup_navmesh(cell, bake)
	t.eq(r3.process_warmup(10), 0, "no bake before physics ready")
	for i in 5:
		r3.mark(Vector2i(i, 0), StreamReadiness.Stage.DATA_LOADED)
		r3.mark(Vector2i(i, 0), StreamReadiness.Stage.PHYSICS_READY)
	t.eq(r3.process_warmup(2), 2, "budget of 2 per frame")
	t.eq(baked.size(), 2, "two baked")
	t.eq(r3.pending_warmups(), 3, "three still queued")
	r3.process_warmup(10)
	t.eq(r3.pending_warmups(), 0, "queue drained")
	t.check(r3.is_stage_ready(Vector2i(4, 0), StreamReadiness.Stage.NAVMESH_READY), "bake marks navmesh ready")

	var r4 := StreamReadiness.new()
	var auto_baked := [0]
	r4.set_auto_warmup(func(_c: Vector2i) -> bool:
		auto_baked[0] += 1
		return true)
	var e := Vector2i(7, 7)
	r4.mark(e, StreamReadiness.Stage.DATA_LOADED)
	t.eq(r4.pending_warmups(), 0, "no auto warmup before physics")
	r4.mark(e, StreamReadiness.Stage.PHYSICS_READY)
	t.eq(r4.pending_warmups(), 1, "auto warmup queued on stream-in")
	r4.process_warmup(4)
	t.eq(auto_baked[0], 1, "auto bake ran once")
	t.check(r4.is_stage_ready(e, StreamReadiness.Stage.NAVMESH_READY), "auto warmup completes navmesh stage")

	var r5 := StreamReadiness.new()
	r5.max_warmup_attempts = 2
	var f := Vector2i(2, 2)
	r5.mark(f, StreamReadiness.Stage.DATA_LOADED)
	r5.mark(f, StreamReadiness.Stage.PHYSICS_READY)
	r5.warmup_navmesh(f, func(_c: Vector2i) -> bool: return false)
	r5.process_warmup(1)
	r5.process_warmup(1)
	t.eq(r5.warmup_failed, [f], "failing bake given up after max attempts")
	t.eq(r5.pending_warmups(), 0, "failed warmup removed")


func _replication(t) -> void:
	t.current = "stream state replication"
	var srv := StreamStateReplication.new()
	srv.allowed_radius = 4
	srv.max_center_error = 1
	var cl := StreamStateReplication.Client.new(5)
	srv.set_client_position("p1", Vector2i(10, 10))
	cl.set_ready(Vector2i(10, 10), true)
	cl.set_ready(Vector2i(11, 9), true)
	cl.set_ready(Vector2i(8, 12), true)
	var p1 := cl.build_report(Vector2i(10, 10))
	t.eq(p1["base"], 0, "first report is full")
	t.eq(p1["bits"].size(), StreamStateReplication.bytes_for(5), "bitset size matches window")
	var wire := StreamStateReplication.serialize(p1)
	var back := StreamStateReplication.deserialize(wire)
	t.eq(back["center"], Vector2i(10, 10), "wire round trip: centre")
	t.eq(back["bits"], p1["bits"], "wire round trip: bits")
	t.eq(StreamStateReplication.deserialize(wire.slice(0, 5)).size(), 0, "truncated packet rejected")
	var r1 := srv.apply_report("p1", back)
	t.check(bool(r1["ok"]), "full report accepted")
	t.eq(r1["ack"], 1, "ack is version 1")
	t.check(srv.is_ready("p1", Vector2i(11, 9)), "server sees ready cell")
	t.check(not srv.is_ready("p1", Vector2i(9, 9)), "unreported cell not ready")
	cl.on_ack(1)

	# delta: add one, drop one, move the window by one cell
	cl.set_ready(Vector2i(12, 10), true)
	cl.set_ready(Vector2i(8, 12), false)
	srv.set_client_position("p1", Vector2i(11, 10))
	var p2 := cl.build_report(Vector2i(11, 10))
	t.eq(p2["base"], 1, "delta relative to acked version")
	var ones := 0
	for b: int in p2["bits"]:
		for k in 8:
			ones += (b >> k) & 1
	t.eq(ones, 2, "delta carries only the two changed cells")
	var r2 := srv.apply_report("p1", p2)
	t.check(bool(r2["ok"]), "delta accepted")
	t.eq(srv.ready_set("p1").size(), 3, "server set after delta")
	t.check(srv.is_ready("p1", Vector2i(12, 10)) and not srv.is_ready("p1", Vector2i(8, 12)), "delta applied correctly")

	# interest management
	var rel := srv.server_relevant("p1", [Vector2i(12, 10), Vector2i(0, 0), Vector2i(10, 10)])
	t.eq(rel, [Vector2i(12, 10), Vector2i(10, 10)], "relevance = interest intersect ready")
	t.eq(srv.server_missing("p1", [Vector2i(12, 10), Vector2i(0, 0)]), [Vector2i(0, 0)], "missing cells listed")

	# packet loss: p2's ack lost, client sends v3 still relative to acked v1
	cl.set_ready(Vector2i(13, 10), true)
	var p3 := cl.build_report(Vector2i(11, 10))
	t.eq(p3["base"], 1, "unacked report: base stays at last acked version")
	var r3 := srv.apply_report("p1", p3)
	t.check(bool(r3["ok"]) and srv.is_ready("p1", Vector2i(13, 10)) and srv.is_ready("p1", Vector2i(12, 10)), "lossy path converges")
	# duplicate / reordered old report
	var dup := srv.apply_report("p1", p2)
	t.check(not bool(dup["ok"]) and dup["reason"] == "old", "old version ignored")
	t.eq(dup["ack"], 3, "old report re-acks newest")
	cl.on_ack(3)
	t.eq(cl.acked_version, 3, "client advances ack")

	# server lost history -> need_full -> full resync
	srv.history_size = 1
	cl.set_ready(Vector2i(9, 10), true)
	var p4 := cl.build_report(Vector2i(11, 10))
	srv.apply_report("p1", p4)  # history now holds only v4
	var p5 := cl.build_report(Vector2i(11, 10))  # still based on acked v3
	var r5 := srv.apply_report("p1", p5)
	t.check(bool(r5["need_full"]), "unknown base asks for a full report")
	cl.request_full()
	var p6 := cl.build_report(Vector2i(11, 10))
	t.eq(p6["base"], 0, "resync is a full report")
	var r6 := srv.apply_report("p1", p6)
	t.check(bool(r6["ok"]) and srv.ready_set("p1").size() == 5, "full resync restores the set")

	# anti-cheat
	var srv2 := StreamStateReplication.new()
	srv2.allowed_radius = 2
	srv2.max_center_error = 1
	srv2.max_report_radius = 6
	srv2.violation_limit = 2
	srv2.set_client_position("evil", Vector2i(0, 0))
	var bad := StreamStateReplication.Client.new(6)
	bad.set_ready(Vector2i(1, 1), true)
	bad.set_ready(Vector2i(6, 6), true)
	var rb := srv2.apply_report("evil", bad.build_report(Vector2i(0, 0)))
	t.eq(rb["stripped"], 1, "claim beyond allowed radius stripped")
	t.check(srv2.is_ready("evil", Vector2i(1, 1)) and not srv2.is_ready("evil", Vector2i(6, 6)), "only plausible claims kept")
	t.eq(srv2.violations("evil"), 1, "violation counted")
	var far := StreamStateReplication.Client.new(3)
	far.build_report(Vector2i(0, 0))
	var rf := srv2.apply_report("evil", far.build_report(Vector2i(50, 50)))
	t.check(not bool(rf["ok"]) and rf["reason"] == "center", "window far from the real position rejected")
	t.check(srv2.is_flagged("evil"), "repeat offender flagged")
	var huge := StreamStateReplication.Client.new(9)
	t.check(not bool(srv2.apply_report("evil", huge.build_report(Vector2i(0, 0)))["ok"]), "oversized report radius rejected")
	var nopos := StreamStateReplication.new()
	t.eq(nopos.apply_report("ghost", cl.build_report(Vector2i(0, 0)))["reason"], "no_position", "unknown position cannot report")
