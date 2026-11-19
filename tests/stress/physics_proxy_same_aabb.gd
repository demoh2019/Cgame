# Isolated low-level broadphase benchmark for unchanged shape bounds.
# The SceneTree caller provides frame statistics via _frame_statistics().
extends RefCounted


func run_2d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var count := 1024 * scale
	var bodies: Array[RID] = []
	var transforms: Array[Transform2D] = []
	bodies.resize(count)
	transforms.resize(count)
	var start_creation := Time.get_ticks_usec()
	for i in range(count):
		var xform := Transform2D(0.0, Vector2(float(i % 1024) * 4.0, float(int(i / 1024)) * 4.0))
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body
		transforms[i] = xform
	var creation_ms := float(Time.get_ticks_usec() - start_creation) / 1000.0
	PhysicsServer2D.space_set_active(space, true)
	await tree.physics_frame

	var update_us := 0
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		var begin := Time.get_ticks_usec()
		for i in range(count):
			PhysicsServer2D.body_set_state(bodies[i], PhysicsServer2D.BODY_STATE_TRANSFORM, transforms[i])
		update_us += Time.get_ticks_usec() - begin
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))

	var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
	var last_position := transforms[count - 1].origin
	var first_hit := state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(-2, 0), Vector2(2, 0)))
	var last_hit := state.intersect_ray(PhysicsRayQueryParameters2D.create(
			last_position + Vector2(-2, 0), last_position + Vector2(2, 0)))
	var valid_hits := not first_hit.is_empty() and not last_hit.is_empty()
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	bodies.clear()
	transforms.clear()
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	if not valid_hits or peak_pairs != 0:
		return {"error": "2D unchanged-AABB proxy queries or collision pair regression"}
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	return {"bodies": count, "physics_frames": frames, "creation_ms": creation_ms,
			"unchanged_transform_updates_ms": float(update_us) / 1000.0,
			"ns_per_update": float(update_us) * 1000.0 / float(maxi(1, count * frames)),
			"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
			"frame_interval_ms": stats, "frame_p95_ms": stats["p95"]}


func run_3d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var count := 1024 * scale
	var bodies: Array[RID] = []
	var transforms: Array[Transform3D] = []
	bodies.resize(count)
	transforms.resize(count)
	var start_creation := Time.get_ticks_usec()
	for i in range(count):
		var xform := Transform3D(Basis(), Vector3(float(i % 128) * 4.0,
				float(int(i / 128) % 128) * 4.0, float(int(i / 16384)) * 4.0))
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
		transforms[i] = xform
	var creation_ms := float(Time.get_ticks_usec() - start_creation) / 1000.0
	PhysicsServer3D.space_set_active(space, true)
	await tree.physics_frame

	var update_us := 0
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		var begin := Time.get_ticks_usec()
		for i in range(count):
			PhysicsServer3D.body_set_state(bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, transforms[i])
		update_us += Time.get_ticks_usec() - begin
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))

	var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
	var last_position := transforms[count - 1].origin
	var first_hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-2, 0, 0), Vector3(2, 0, 0)))
	var last_hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(
			last_position + Vector3(-2, 0, 0), last_position + Vector3(2, 0, 0)))
	var valid_hits := not first_hit.is_empty() and not last_hit.is_empty()
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	bodies.clear()
	transforms.clear()
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	if not valid_hits or peak_pairs != 0:
		return {"error": "3D unchanged-AABB proxy queries or collision pair regression"}
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	return {"bodies": count, "physics_frames": frames, "creation_ms": creation_ms,
			"unchanged_transform_updates_ms": float(update_us) / 1000.0,
			"ns_per_update": float(update_us) * 1000.0 / float(maxi(1, count * frames)),
			"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
			"frame_interval_ms": stats, "frame_p95_ms": stats["p95"]}
