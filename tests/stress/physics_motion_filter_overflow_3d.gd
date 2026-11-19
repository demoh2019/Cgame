extends RefCounted
## Regression for motion BVH candidate collection in dense 3D spaces.
## Thousands of areas occupy the swept AABB but must never consume the
## finite collision-candidate budget needed by a real solid obstacle.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)

	var mover := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(mover, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_add_shape(mover, sphere)
	PhysicsServer3D.body_set_state(mover, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	PhysicsServer3D.body_set_space(mover, space)

	var obstacle := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(obstacle, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(obstacle, sphere)
	PhysicsServer3D.body_set_state(obstacle, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)))
	PhysicsServer3D.body_set_space(obstacle, space)
	PhysicsServer3D.space_set_active(space, true)
	await tree.physics_frame

	var query := PhysicsTestMotionParameters3D.new()
	query.from = Transform3D.IDENTITY
	query.motion = Vector3(3.0, 0.0, 0.0)
	var baseline_hit := PhysicsServer3D.body_test_motion(mover, query)

	var count := 2048 + 256 * mini(scale, 16)
	var areas: Array[RID] = []
	areas.resize(count)
	var start_creation := Time.get_ticks_usec()
	for i in range(count):
		var area := PhysicsServer3D.area_create()
		PhysicsServer3D.area_set_collision_layer(area, 0)
		PhysicsServer3D.area_set_collision_mask(area, 0)
		PhysicsServer3D.area_add_shape(area, sphere)
		PhysicsServer3D.area_set_transform(area, Transform3D(Basis(), Vector3(1.5, 0.0, 0.0)))
		PhysicsServer3D.area_set_space(area, space)
		areas[i] = area
	var creation_ms := float(Time.get_ticks_usec() - start_creation) / 1000.0
	await tree.physics_frame

	var trials := mini(frames, 100)
	var misses := 0
	var begin := Time.get_ticks_usec()
	for i in range(trials):
		if not PhysicsServer3D.body_test_motion(mover, query):
			misses += 1
	var query_ms := float(Time.get_ticks_usec() - begin) / 1000.0

	# Excluding the only solid body must still yield no hit. Areas must not
	# become false positives, regardless of how many proxies overlap the ray.
	PhysicsServer3D.body_add_collision_exception(mover, obstacle)
	var exception_rejected := not PhysicsServer3D.body_test_motion(mover, query)

	PhysicsServer3D.space_set_active(space, false)
	for area in areas:
		PhysicsServer3D.free_rid(area)
	PhysicsServer3D.free_rid(mover)
	PhysicsServer3D.free_rid(obstacle)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)

	if not baseline_hit or misses != 0 or not exception_rejected:
		return {"error": "3D motion candidate filtering lost a solid obstacle or ignored collision exceptions",
				"baseline_hit": baseline_hit, "missed_queries": misses, "exception_rejected": exception_rejected}
	return {"areas": count, "queries": trials, "creation_ms": creation_ms,
			"motion_queries_ms": query_ms, "candidate_filter_verified": true}
