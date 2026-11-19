# Compare the same box-box contact geometry with identity and rotated bases.
# Both scenes reassert overlapping transforms so the narrow phase stays active.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, rotated: bool) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(2.0, 2.0, 2.0))
	var basis := Basis(Vector3.UP, 0.37) if rotated else Basis()
	var count := mini(256 * scale, 4096)
	var static_bodies: Array[RID] = []
	var dynamic_bodies: Array[RID] = []
	var dynamic_poses: Array[Transform3D] = []
	static_bodies.resize(count)
	dynamic_bodies.resize(count)
	dynamic_poses.resize(count)

	var creation_start := Time.get_ticks_usec()
	for i in range(count):
		var origin := Vector3(float(i % 64) * 7.0, 0.0, float(int(i / 64)) * 7.0)
		origin = basis * origin
		var ground := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(ground, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(ground, shape)
		PhysicsServer3D.body_set_state(ground, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(basis, origin))
		PhysicsServer3D.body_set_space(ground, space)
		static_bodies[i] = ground

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		var pose := Transform3D(basis, origin + basis * Vector3(1.5, 0.0, 0.0))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
		PhysicsServer3D.body_set_space(body, space)
		dynamic_bodies[i] = body
		dynamic_poses[i] = pose
	var creation_ms := float(Time.get_ticks_usec() - creation_start) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var update_us := 0
	var last_tick := Time.get_ticks_usec()
	var error := ""
	for frame in range(frames):
		# Reassert the identical orientation but alternate the overlap
		# distance. SAT results must not be reused from a stale separation.
		var begin := Time.get_ticks_usec()
		for i in range(count):
			var pose: Transform3D = dynamic_poses[i]
			pose.origin += basis * Vector3(0.03 if frame % 2 == 0 else -0.03, 0.0, 0.0)
			PhysicsServer3D.body_set_state(dynamic_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
		update_us += Time.get_ticks_usec() - begin
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [dynamic_bodies[0], dynamic_bodies[int(count / 2)], dynamic_bodies[count - 1]]:
			var position: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not position.origin.is_finite() or not velocity.is_finite():
				error = "Non-finite 3D box contact transform or velocity"
				break
		if error != "":
			break

	PhysicsServer3D.space_set_active(space, false)
	for body in dynamic_bodies:
		PhysicsServer3D.free_rid(body)
	for body in static_bodies:
		PhysicsServer3D.free_rid(body)
	dynamic_bodies.clear()
	static_bodies.clear()
	dynamic_poses.clear()
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	if error != "":
		return {"error": error}
	if peak_pairs == 0:
		return {"error": "No box-box pairs were recorded by the physics server"}
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	return {
		"box_pairs": count, "total_bodies": count * 2,
		"rotated_fallback": rotated, "physics_frames": frames,
		"creation_ms": creation_ms, "transform_update_ms": float(update_us) / 1000.0,
		"peak_collision_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"],
	}
