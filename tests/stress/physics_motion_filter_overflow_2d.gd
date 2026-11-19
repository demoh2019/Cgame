extends RefCounted
## Regression for 2D kinematic body motion broadphase filtering.
## Filter out thousands of areas and non-colliding rigid bodies before
## consuming the finite 2048-candidate motion scratch buffer.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)

	var mover := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(mover, PhysicsServer2D.BODY_MODE_KINEMATIC)
	PhysicsServer2D.body_add_shape(mover, circle)
	PhysicsServer2D.body_set_state(mover, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	PhysicsServer2D.body_set_space(mover, space)

	var obstacle := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(obstacle, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(obstacle, circle)
	PhysicsServer2D.body_set_state(obstacle, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(2.0, 0.0)))
	PhysicsServer2D.body_set_space(obstacle, space)
	PhysicsServer2D.space_set_active(space, true)
	await tree.physics_frame

	var query := PhysicsTestMotionParameters2D.new()
	query.from = Transform2D.IDENTITY
	query.motion = Vector2(3.0, 0.0)
	var baseline_hit := PhysicsServer2D.body_test_motion(mover, query)

	# Areas should never occupy body-motion candidate slots.
	var area_count := 2048 + 256 * mini(scale, 16)
	var areas: Array[RID] = []
	areas.resize(area_count)
	var started := Time.get_ticks_usec()
	for i in range(area_count):
		var area := PhysicsServer2D.area_create()
		PhysicsServer2D.area_set_collision_layer(area, 0)
		PhysicsServer2D.area_set_collision_mask(area, 0)
		PhysicsServer2D.area_add_shape(area, circle)
		PhysicsServer2D.area_set_transform(area, Transform2D(0.0, Vector2(1.5, 0.0)))
		PhysicsServer2D.area_set_space(area, space)
		areas[i] = area

	# Non-matching collision layers also must not occupy the finite buffer.
	var unrelated: Array[RID] = []
	for i in range(128):
		var wrong_layer := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(wrong_layer, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(wrong_layer, circle)
		PhysicsServer2D.body_set_collision_layer(wrong_layer, 2)
		PhysicsServer2D.body_set_collision_mask(wrong_layer, 0)
		PhysicsServer2D.body_set_state(wrong_layer, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(1.5, 0.0)))
		PhysicsServer2D.body_set_space(wrong_layer, space)
		unrelated.append(wrong_layer)

	# Reinsert the valid collider after irrelevant proxies to exercise
	# BVH insertion orders that used to fill the bounded buffer.
	PhysicsServer2D.body_set_space(obstacle, RID())
	PhysicsServer2D.body_set_space(obstacle, space)
	var creation_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await tree.physics_frame

	var misses := 0
	var trials := maxi(1, mini(frames, 100))
	var begin := Time.get_ticks_usec()
	for i in range(trials):
		if not PhysicsServer2D.body_test_motion(mover, query):
			misses += 1
	var query_ms := float(Time.get_ticks_usec() - begin) / 1000.0

	# Both query-side exclusions and body collision exceptions must work.
	var excluded: Array[RID] = [obstacle]
	query.exclude_bodies = excluded
	var query_excluded := not PhysicsServer2D.body_test_motion(mover, query)
	query.exclude_bodies = []

	PhysicsServer2D.body_add_collision_exception(mover, obstacle)
	var exception_rejected := not PhysicsServer2D.body_test_motion(mover, query)
	PhysicsServer2D.body_remove_collision_exception(mover, obstacle)

	# A stationary recovery test must not divide by zero when forming
	# motion_normal. There is no initial overlap with the valid obstacle.
	query.motion = Vector2.ZERO
	var zero_motion_safe := not PhysicsServer2D.body_test_motion(mover, query)

	PhysicsServer2D.space_set_active(space, false)
	for area in areas:
		PhysicsServer2D.free_rid(area)
	for wrong_layer in unrelated:
		PhysicsServer2D.free_rid(wrong_layer)
	PhysicsServer2D.free_rid(mover)
	PhysicsServer2D.free_rid(obstacle)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(space)

	if not baseline_hit or misses != 0 or not query_excluded or not exception_rejected or not zero_motion_safe:
		return {"error": "2D motion candidate filtering lost a solid obstacle, exception or stationary safety",
				"baseline_hit": baseline_hit, "missed_queries": misses,
				"query_excluded": query_excluded, "exception_rejected": exception_rejected,
				"zero_motion_safe": zero_motion_safe}
	return {"areas": area_count, "filtered_bodies": unrelated.size(), "queries": trials,
			"creation_ms": creation_ms, "motion_queries_ms": query_ms,
			"candidate_filter_verified": true, "zero_motion_verified": true}
