extends RefCounted
## Deterministic rigid-body solver, rollback integration, lag-compensation rewind and timeline.

const Phys = preload("res://scripts/shared/deterministic_physics.gd")
const PhysicsRollback = preload("res://scripts/shared/physics_rollback.gd")
const PhysicsTimeline = preload("res://scripts/shared/physics_timeline.gd")
const RollbackNetcode = preload("res://scripts/shared/rollback_netcode.gd")

const DT: float = 1.0 / 60.0


func _ground(w: Phys) -> void:
	w.add_body(0, Phys.Shape.BOX, 0.0, Vector3(0, -1, 0), Vector3(50, 1, 50), Quaternion.IDENTITY, 0.6, 0.0)


func _pile(w: Phys) -> void:
	_ground(w)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 8:
		var pos: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 1.0 + float(i) * 1.1, rng.randf_range(-1.0, 1.0))
		var rot: Quaternion = Quaternion(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf_range(0.0, 3.0))
		if i % 2 == 0:
			w.add_body(i + 1, Phys.Shape.BOX, 1.0, pos, Vector3(0.5, 0.4, 0.3), rot, 0.5, 0.1)
		else:
			w.add_body(i + 1, Phys.Shape.SPHERE, 1.0, pos, Vector3(0.45, 0, 0), rot, 0.4, 0.3)


func _run_pile(steps: int) -> Phys:
	var w: Phys = Phys.new()
	_pile(w)
	for _i in steps:
		w.step(DT)
	return w


func _rollback_world() -> PhysicsRollback:
	var pr: PhysicsRollback = PhysicsRollback.new()
	pr.world.add_body(0, Phys.Shape.BOX, 0.0, Vector3(0, -1, 0), Vector3(50, 1, 50), Quaternion.IDENTITY, 0.6, 0.0)
	pr.world.add_body(1, Phys.Shape.SPHERE, 1.0, Vector3(-2, 0.5, 0), Vector3(0.5, 0, 0), Quaternion.IDENTITY, 0.4, 0.2)
	pr.world.add_body(2, Phys.Shape.SPHERE, 1.0, Vector3(2, 0.5, 0), Vector3(0.5, 0, 0), Quaternion.IDENTITY, 0.4, 0.2)
	pr.world.add_body(3, Phys.Shape.BOX, 1.0, Vector3(0, 0.5, 0), Vector3(0.5, 0.5, 0.5), Quaternion.IDENTITY, 0.5, 0.0)
	pr.bind_player(10, 1)
	pr.bind_player(20, 2)
	return pr


func _in_a(f: int) -> Dictionary:
	return {"force": Vector3(30.0, 0.0, sin(float(f) * 0.3) * 10.0)} if f % 5 != 0 else {}


func _in_b(f: int) -> Dictionary:
	return {"force": Vector3(-30.0, 0.0, 0.0)} if f % 7 < 4 else {"force": Vector3(0.0, 0.0, 15.0)}


func run(t) -> void:
	t.current = "stack settles and sleeps"
	var w: Phys = Phys.new()
	_ground(w)
	for i in 4:
		w.add_body(i + 1, Phys.Shape.BOX, 1.0, Vector3(0, 0.5 + float(i), 0), Vector3(0.5, 0.5, 0.5), Quaternion.IDENTITY, 0.6, 0.0)
	var slept_at: int = -1
	for s in 600:
		w.step(DT)
		if slept_at < 0 and w.sleeping_count() == 4:
			slept_at = s
	t.check(slept_at >= 0, "all four boxes fall asleep")
	var ok_pos: bool = true
	for i in 4:
		var p: Vector3 = w.get_position(i + 1)
		var expect_y: float = 0.5 + float(i)
		if absf(p.y - expect_y) > 0.06 or absf(p.x) > 0.1 or absf(p.z) > 0.1:
			ok_pos = false
	t.check(ok_pos, "stack stays upright at ~1 m spacing")
	t.eq(w.get_velocity(4), Vector3.ZERO, "sleeping body has zero velocity")
	w.apply_impulse(4, Vector3(0, 5, 0))
	t.check(not w.is_asleep(4), "impulse wakes a sleeper")

	t.current = "restitution bounce"
	var wb: Phys = Phys.new()
	_ground(wb)
	wb.add_body(1, Phys.Shape.SPHERE, 1.0, Vector3(0, 5.5, 0), Vector3(0.5, 0, 0), Quaternion.IDENTITY, 0.3, 0.8)
	var impact: float = 0.0
	var peak_up: float = 0.0
	var apex: float = 0.0
	var bounced: bool = false
	for _i in 200:
		var vy_before: float = wb.get_velocity(1).y
		wb.step(DT)
		var vy: float = wb.get_velocity(1).y
		if not bounced and vy_before < -1.0 and vy > 0.0:
			bounced = true
			impact = -vy_before
			peak_up = vy
		elif bounced:
			apex = maxf(apex, wb.get_position(1).y)
	t.check(bounced, "sphere bounces")
	t.check(peak_up > 0.6 * impact and peak_up < 0.95 * impact, "rebound speed ~ restitution * impact (%.2f vs %.2f)" % [peak_up, impact])
	t.check(apex > 2.5 and apex < 3.9, "second apex ~ e^2 * drop height (%.2f)" % apex)

	t.current = "determinism"
	var w1: Phys = _run_pile(240)
	var w2: Phys = _run_pile(240)
	t.eq(w1.checksum(), w2.checksum(), "two runs give identical checksums")
	t.eq(w1.snapshot(), w2.snapshot(), "two runs give identical bytes")
	var w3: Phys = _run_pile(241)
	t.check(w3.checksum() != w1.checksum(), "checksum changes as the world evolves")
	var moved: bool = false
	for i in range(1, 9):
		if w1.get_position(i).y < 6.0:
			moved = true
	t.check(moved, "pile fell")

	t.current = "snapshot restore"
	var ws: Phys = _run_pile(60)
	var snap: PackedByteArray = ws.snapshot()
	for _i in 60:
		ws.step(DT)
	var cs_a: int = ws.checksum()
	ws.restore(snap)
	t.eq(ws.snapshot(), snap, "restore reproduces the snapshot bytes")
	for _i in 60:
		ws.step(DT)
	t.eq(ws.checksum(), cs_a, "resimulating from a restore matches the original run")
	var fresh: Phys = Phys.new()
	t.check(fresh.restore(snap), "restore into a fresh world")
	for _i in 60:
		fresh.step(DT)
	t.eq(fresh.checksum(), cs_a, "fresh world continues identically")

	t.current = "rollback of a late input matches lockstep"
	var frames: int = 40
	var ref: PhysicsRollback = _rollback_world()
	var ref_state: Dictionary = ref.initial_state()
	for f in frames:
		ref_state = ref.step_state(ref_state, {10: _in_a(f), 20: _in_b(f)}, DT)
	var pr: PhysicsRollback = _rollback_world()
	var net: RollbackNetcode = RollbackNetcode.new()
	pr.setup_net(net, [10, 20], [10], DT, 0, 8)
	for f in frames:
		net.add_local_input(10, _in_a(f))
		net.advance()
		if f - 3 >= 0:
			net.add_remote_input(20, f - 3, _in_b(f - 3))
	for f in range(frames - 3, frames):
		net.add_remote_input(20, f, _in_b(f))
	net.process()
	t.eq(net.frame, frames, "netcode reached the target frame")
	t.check(net.rollbacks > 0, "late remote inputs caused rollbacks")
	t.eq(pr.state_checksum(net.get_state()), ref.state_checksum(ref_state), "rolled-back state equals lockstep reference")
	t.eq(net.get_state()["phys"], ref_state["phys"], "rolled-back bytes identical")

	t.current = "rewind query"
	var lc: PhysicsRollback = PhysicsRollback.new()
	lc.world.gravity = Vector3.ZERO
	lc.world.add_body(1, Phys.Shape.SPHERE, 1.0, Vector3(0, 0, 0), Vector3(0.5, 0, 0))
	lc.world.set_velocity(1, Vector3(10, 0, 0))
	var st: Dictionary = lc.initial_state()
	for _i in 60:
		st = lc.step_state(st, {}, DT)
	var now_x: float = lc.world.get_position(1).x
	t.near(now_x, 10.0, 0.2, "ball moved ~10 m in 1 s")
	var down: Vector3 = Vector3(0, 0, -1)
	var past: Dictionary = lc.rewind_query(0.0, Vector3(0, 0, 5), down)
	t.check(bool(past["hit"]) and int(past["id"]) == 1, "rewound ray hits the ball where it was")
	var present: Dictionary = lc.rewind_query(lc.newest_time(), Vector3(0, 0, 5), down)
	t.check(not bool(present["hit"]), "same ray misses where the ball is now")
	var present_hit: Dictionary = lc.rewind_query(lc.newest_time(), Vector3(now_x, 0, 5), down)
	t.check(bool(present_hit["hit"]), "ray at the current position hits at current time")
	var past_miss: Dictionary = lc.rewind_query(0.0, Vector3(now_x, 0, 5), down)
	t.check(not bool(past_miss["hit"]), "ray at the current position misses in the past")
	var mid: Dictionary = lc.rewind_query(0.5 + DT * 0.5, Vector3(5.0 + 10.0 * DT * 0.5, 0, 5), down)
	t.check(bool(mid["hit"]), "sub-frame time interpolates between snapshots")
	t.near(float(past["t"]), 4.5, 0.01, "hit distance on the sphere surface")

	t.current = "box and sphere raycasts"
	var wr: Phys = Phys.new()
	wr.add_body(1, Phys.Shape.BOX, 0.0, Vector3(0, 0, 0), Vector3(1, 1, 1))
	var hr: Dictionary = wr.raycast(Vector3(-5, 0, 0), Vector3(1, 0, 0))
	t.check(bool(hr["hit"]) and absf(float(hr["t"]) - 4.0) < 0.001, "ray hits box face")
	t.check(not bool(wr.raycast(Vector3(-5, 3, 0), Vector3(1, 0, 0))["hit"]), "ray passes above box")

	t.current = "timeline"
	var tl: PhysicsTimeline = PhysicsTimeline.new()
	var wt: Phys = Phys.new()
	_pile(wt)
	wt.timeline = tl
	for _i in 30:
		wt.step(DT)
	t.eq(tl.record_count(), 30, "one record per step")
	var rec: Dictionary = tl.records()[29]
	for phase in PhysicsTimeline.PHASES:
		var seen: bool = false
		for ev in rec["phases"]:
			if ev["name"] == phase:
				seen = true
		t.check(seen, "phase recorded: " + phase)
	t.check(int(rec["bodies"]) == 9, "body count recorded")
	var rep: Dictionary = tl.report()
	t.eq(rep["steps"], 30, "report step count")
	t.check((rep["phases"] as Dictionary).has("narrowphase"), "report has narrowphase")
	t.check(int(rep["max_contacts"]) > 0, "contacts counted")
	t.check(tl.report_text().begins_with("physics:"), "report text")
	var parsed: Variant = JSON.parse_string(tl.export_json())
	t.check(parsed is Dictionary and (parsed as Dictionary).has("traceEvents"), "export parses as JSON with traceEvents")
	var evs: Array = (parsed as Dictionary)["traceEvents"]
	var has_x: bool = false
	for e in evs:
		if e["ph"] == "X" and e["name"] == "solve":
			has_x = true
	t.check(has_x, "trace has complete events for phases")
	tl.capacity = 10
	wt.step(DT)
	t.check(tl.record_count() <= 10, "ring buffer is bounded")
