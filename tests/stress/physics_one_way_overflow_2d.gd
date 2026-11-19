extends RefCounted
## Regression for one-way recovery exclusions beyond 32 pairs.
## Dense platforms on the non-colliding side must not turn into solid walls.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)
	var mover := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(mover, PhysicsServer2D.BODY_MODE_KINEMATIC)
	PhysicsServer2D.body_add_shape(mover, circle)
	PhysicsServer2D.body_set_state(mover, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	PhysicsServer2D.body_set_space(mover, space)

	# The moving circle overlaps these one-way platforms from below.
	# Their recovery contacts have an invalid one-way direction.
	var platform_count := 64 + 32 * mini(scale, 8)
	var platforms: Array[RID] = []
	platforms.resize(platform_count)
	var creation_started := Time.get_ticks_usec()
	for i in range(platform_count):
		var platform := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(platform, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(platform, circle)
		PhysicsServer2D.body_set_shape_as_one_way_collision(platform, 0, true, 0.1, Vector2(0.0, 1.0))
		PhysicsServer2D.body_set_state(platform, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(0.0, -0.8)))
		PhysicsServer2D.body_set_space(platform, space)
		platforms[i] = platform

	PhysicsServer2D.space_set_active(space, true)
	await tree.physics_frame
	var creation_ms := float(Time.get_ticks_usec() - creation_started) / 1000.0

	var query := PhysicsTestMotionParameters2D.new()
	query.from = Transform2D.IDENTITY
	query.motion = Vector2(3.0, 0.0)
	var result := PhysicsTestMotionResult2D.new()
	var trials := maxi(1, mini(frames, 40))
	var misses := 0
	var started := Time.get_ticks_usec()
	for i in range(trials):
		if PhysicsServer2D.body_test_motion(mover, query, result):
			misses += 1
	var empty_query_ms := float(Time.get_ticks_usec() - started) / 1000.0

	# A real solid obstacle still needs to win over all ignored platforms.
	var obstacle := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(obstacle, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(obstacle, circle)
	PhysicsServer2D.body_set_state(obstacle, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(2.0, 0.0)))
	PhysicsServer2D.body_set_space(obstacle, space)
	await tree.physics_frame
	var solid_hit := PhysicsServer2D.body_test_motion(mover, query, result)
	var solid_valid := (
		solid_hit and result.get_collider_rid() == obstacle
		and result.get_collision_safe_fraction() > 0.1
		and result.get_collision_safe_fraction() < 0.8
	)

	# Compound bodies may reuse the same Shape2D RID at different offsets.
	# The second shape must still find its own solid collider.
	PhysicsServer2D.body_add_shape(mover, circle, Transform2D(0.0, Vector2(0.0, 5.0)))
	var high_obstacle := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(high_obstacle, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(high_obstacle, circle)
	PhysicsServer2D.body_set_state(high_obstacle, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(1.4, 5.0)))
	PhysicsServer2D.body_set_space(high_obstacle, space)
	await tree.physics_frame
	var compound_hit := PhysicsServer2D.body_test_motion(mover, query, result)
	var compound_valid := (
		compound_hit and result.get_collider_rid() == high_obstacle
		and result.get_collision_safe_fraction() < 0.25
	)

	PhysicsServer2D.space_set_active(space, false)
	for platform in platforms:
		PhysicsServer2D.free_rid(platform)
	PhysicsServer2D.free_rid(high_obstacle)
	PhysicsServer2D.free_rid(obstacle)
	PhysicsServer2D.free_rid(mover)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(space)

	if misses != 0 or not solid_valid or not compound_valid:
		return {"error": "2D one-way pair overflow or compound-shape collision regressed",
			"platforms": platform_count, "unexpected_hits": misses,
			"solid_valid": solid_valid, "compound_valid": compound_valid}
	return {"platforms": platform_count, "queries": trials,
		"creation_ms": creation_ms, "empty_query_ms": empty_query_ms,
		"one_way_overflow_verified": true, "compound_shared_shape_verified": compound_valid}
