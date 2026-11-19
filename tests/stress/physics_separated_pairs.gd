extends RefCounted
## Persistent broadphase AABB overlaps without narrowphase contacts.
## Compare identical cases on builds before/after negative manifold caching.


func run(tree: SceneTree, scale: int, frames: int, dimension: int) -> Dictionary:
	if dimension == 2:
		return await _run_2d(tree, scale, frames)
	return await _run_3d(tree, scale, frames)


func _run_2d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var count := mini(128 * scale, 16384)
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(shape, Vector2(60.0, 6.0))
	var angle := PI / 4.0
	var normal := Vector2(-sin(angle), cos(angle))
	var statics: Array[RID] = []
	var bodies: Array[RID] = []
	statics.resize(count)
	bodies.resize(count)
	var created := Time.get_ticks_usec()
	for i in range(count):
		var position := Vector2(float(i % 64) * 180.0, float(int(i / 64)) * 180.0)
		var floor := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(floor, shape)
		PhysicsServer2D.body_set_state(floor, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(angle, position))
		PhysicsServer2D.body_set_space(floor, space)
		statics[i] = floor

		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(angle, position + normal * 20.0))
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - created) / 1000.0

	PhysicsServer2D.space_set_active(space, true)
	# Establish the persistent negative narrowphase results before measuring.
	for warmup in range(5):
		await tree.physics_frame
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var state_valid := true
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms,
				float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		peak_pairs = maxi(peak_pairs,
				int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for idx in [0, int(count / 2), count - 1]:
			var pose: Transform2D = PhysicsServer2D.body_get_state(bodies[idx], PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(bodies[idx], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 0.0001:
				state_valid = false
				break
		if not state_valid:
			break

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for floor in statics:
		PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	var result := {
		"dimension": 2, "body_pairs": count, "rigid_bodies": count * 2,
		"creation_ms": creation_ms, "peak_broadphase_pairs": peak_pairs,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"], "state_valid": state_valid,
	}
	if not state_valid or peak_pairs < int(count / 2):
		result["error"] = "2D broadphase near-miss workload did not remain valid"
	return result


func _run_3d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var count := mini(128 * scale, 16384)
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(120.0, 12.0, 10.0))
	var angle := PI / 4.0
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	var basis := Basis(Vector3(0.0, 0.0, 1.0), angle)
	var statics: Array[RID] = []
	var bodies: Array[RID] = []
	statics.resize(count)
	bodies.resize(count)
	var created := Time.get_ticks_usec()
	for i in range(count):
		var position := Vector3(float(i % 64) * 180.0, float(int(i / 64)) * 180.0, 0.0)
		var floor := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(floor, shape)
		PhysicsServer3D.body_set_state(floor, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(basis, position))
		PhysicsServer3D.body_set_space(floor, space)
		statics[i] = floor

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(basis, position + normal * 20.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - created) / 1000.0

	PhysicsServer3D.space_set_active(space, true)
	for warmup in range(5):
		await tree.physics_frame
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var state_valid := true
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms,
				float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		peak_pairs = maxi(peak_pairs,
				int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for idx in [0, int(count / 2), count - 1]:
			var pose: Transform3D = PhysicsServer3D.body_get_state(bodies[idx], PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(bodies[idx], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 0.0001:
				state_valid = false
				break
		if not state_valid:
			break

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for floor in statics:
		PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	var result := {
		"dimension": 3, "body_pairs": count, "rigid_bodies": count * 2,
		"creation_ms": creation_ms, "peak_broadphase_pairs": peak_pairs,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"], "state_valid": state_valid,
	}
	if not state_valid or peak_pairs < int(count / 2):
		result["error"] = "3D broadphase near-miss workload did not remain valid"
	return result
