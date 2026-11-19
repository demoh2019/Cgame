# Compare 2-axis shared-rectangle SAT with the four-axis relative rotation path.
# Run via tests/stress/run.py for CPU/frame/RSS metrics and watchdog.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, orientation: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var rect := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(rect, Vector2(2.0, 2.0))
	var count := mini(256 * scale, 4096)
	var static_bodies: Array[RID] = []
	var dynamic_bodies: Array[RID] = []
	var centers: Array[Vector2] = []
	static_bodies.resize(count)
	dynamic_bodies.resize(count)
	centers.resize(count)
	var basis := Transform2D(0.37 if orientation != 0 else 0.0, Vector2.ZERO)
	var dynamic_x := basis.x
	var dynamic_y := basis.y
	if orientation == 2:
		dynamic_x = dynamic_x.rotated(0.31)
		dynamic_y = dynamic_y.rotated(0.31)

	var creation_start := Time.get_ticks_usec()
	for i in range(count):
		var origin := Vector2(float(i % 64) * 6.0, float(int(i / 64)) * 6.0)
		var ground := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(ground, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(ground, rect)
		PhysicsServer2D.body_set_state(ground, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(basis.x, basis.y, origin))
		PhysicsServer2D.body_set_space(ground, space)
		static_bodies[i] = ground

		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, rect)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		var center := origin + basis.basis_xform(Vector2(1.65, 0.0))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(dynamic_x, dynamic_y, center))
		PhysicsServer2D.body_set_space(body, space)
		dynamic_bodies[i] = body
		centers[i] = center
	var creation_ms := float(Time.get_ticks_usec() - creation_start) / 1000.0
	PhysicsServer2D.space_set_active(space, true)

	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var update_us := 0
	var intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var error := ""
	for frame in range(frames):
		var update_start := Time.get_ticks_usec()
		for i in range(count):
			var offset := basis.basis_xform(Vector2(0.03 if frame % 2 == 0 else -0.03, 0.0))
			PhysicsServer2D.body_set_state(dynamic_bodies[i], PhysicsServer2D.BODY_STATE_TRANSFORM,
					Transform2D(dynamic_x, dynamic_y, centers[i] + offset))
		update_us += Time.get_ticks_usec() - update_start
		await tree.physics_frame
		var tick := Time.get_ticks_usec()
		intervals.append(float(tick - last_tick) / 1000.0)
		last_tick = tick
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [dynamic_bodies[0], dynamic_bodies[int(count / 2)], dynamic_bodies[count - 1]]:
			var pose: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite():
				error = "Non-finite 2D rectangle contact position/velocity"
				break
		if error != "":
			break

	PhysicsServer2D.space_set_active(space, false)
	for body in dynamic_bodies:
		PhysicsServer2D.free_rid(body)
	for body in static_bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(rect)
	PhysicsServer2D.free_rid(space)
	if error != "":
		return {"error": error}
	if peak_pairs == 0:
		return {"error": "No rectangle/rectangle collision pairs were detected"}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"rectangle_pairs": count, "total_bodies": count * 2,
		"orientation": orientation, "same_basis": orientation != 2,
		"physics_frames": frames, "creation_ms": creation_ms,
		"transform_update_ms": float(update_us) / 1000.0,
		"peak_collision_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"],
	}
