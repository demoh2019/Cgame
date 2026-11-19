extends RefCounted
## Contact-heavy RID workloads without Node/SceneTree overhead.
## Scale is intentionally capped: dense contacts grow much faster than sparse bodies.

func run_2d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	PhysicsServer2D.space_set_active(space, true)
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var count := mini(256 * scale, 16384)
	var columns := maxi(2, ceili(sqrt(float(count))))
	var bodies: Array[RID] = []
	bodies.resize(count)
	var creation_started := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i % columns) * 0.85, float(int(i / columns)) * 0.85)))
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - creation_started) / 1000.0
	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var probe: Transform2D = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_TRANSFORM)
	var moved_distance := probe.origin.length()
	var cleanup_started := Time.get_ticks_usec()
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	bodies.clear()
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	var cleanup_ms := float(Time.get_ticks_usec() - cleanup_started) / 1000.0
	if not probe.origin.is_finite():
		return {"error": "Dense 2D physics produced nonfinite coordinates"}
	if peak_pairs == 0:
		return {"error": "Dense 2D bodies generated no contact pairs"}
	return {"bodies": count, "peak_collision_pairs": peak_pairs, "probe_displacement": moved_distance,
			"creation_ms": creation_ms, "cleanup_ms": cleanup_ms, "peak_physics_ms": peak_physics_ms,
			"frame_interval_ms": _frame_statistics(frame_intervals)}


func run_3d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	# Stay below Jolt's default max_bodies (10,240) if selected.
	var count := mini(128 * scale, 8192)
	var side := maxi(2, ceili(pow(float(count), 1.0 / 3.0)))
	var bodies: Array[RID] = []
	bodies.resize(count)
	var creation_started := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % side) * 0.85,
						float(int(i / side) % side) * 0.85, float(int(i / (side * side))) * 0.85)))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - creation_started) / 1000.0
	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var probe: Transform3D = PhysicsServer3D.body_get_state(bodies[0], PhysicsServer3D.BODY_STATE_TRANSFORM)
	var moved_distance := probe.origin.length()
	var cleanup_started := Time.get_ticks_usec()
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	bodies.clear()
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	var cleanup_ms := float(Time.get_ticks_usec() - cleanup_started) / 1000.0
	if not probe.origin.is_finite():
		return {"error": "Dense 3D physics produced nonfinite coordinates"}
	if peak_pairs == 0:
		return {"error": "Dense 3D bodies generated no contact pairs"}
	return {"bodies": count, "peak_collision_pairs": peak_pairs, "probe_displacement": moved_distance,
			"creation_ms": creation_ms, "cleanup_ms": cleanup_ms, "peak_physics_ms": peak_physics_ms,
			"frame_interval_ms": _frame_statistics(frame_intervals)}



# Create and remove bodies *before* their first physics step. Jolt queues
# these additions; without indexed removal this workload can become quadratic.
func run_pending_3d(scale: int) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var count := mini(512 * scale, 8192)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var creation_started := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i) * 4.0, 0.0, 0.0)))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var create_ms := float(Time.get_ticks_usec() - creation_started) / 1000.0
	var cleanup_started := Time.get_ticks_usec()
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	bodies.clear()
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	var cleanup_ms := float(Time.get_ticks_usec() - cleanup_started) / 1000.0
	return {"bodies": count, "create_ms": create_ms, "pending_cleanup_ms": cleanup_ms}


func _frame_statistics(values: Array[float]) -> Dictionary:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var count := sorted_values.size()
	return {
		"min": sorted_values[0],
		"median": sorted_values[int((count - 1) / 2)],
		"p95": sorted_values[mini(count - 1, ceili(float(count) * 0.95) - 1)],
		"p99": sorted_values[mini(count - 1, ceili(float(count) * 0.99) - 1)],
		"max": sorted_values[count - 1],
	}
