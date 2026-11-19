extends RefCounted
## 2D motion queries must filter excluded proxies before the 2048-entry cap.
## Also exercises the nearest obstacle and a stationary recovery sweep.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)
	var mover := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(mover, PhysicsServer2D.BODY_MODE_KINEMATIC)
	PhysicsServer2D.body_add_shape(mover, circle)
	PhysicsServer2D.body_set_space(mover, space)

	var query := PhysicsTestMotionParameters2D.new()
	query.from = Transform2D.IDENTITY
	query.motion = Vector2(4.0, 0.0)
	var result := PhysicsTestMotionResult2D.new()

	var excluded_bodies: Array[RID] = []
	var count := 2048 + 128 * mini(scale, 8)
	excluded_bodies.resize(count)
	var start_creation := Time.get_ticks_usec()
	for i in range(count):
		var decoy := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(decoy, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(decoy, circle)
		PhysicsServer2D.body_set_state(decoy, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(1.8, 0.0)))
		PhysicsServer2D.body_set_space(decoy, space)
		excluded_bodies[i] = decoy

	var near_body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(near_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(near_body, circle)
	PhysicsServer2D.body_set_state(near_body, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(1.4, 0.0)))
	PhysicsServer2D.body_set_space(near_body, space)

	var far_body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(far_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(far_body, circle)
	PhysicsServer2D.body_set_state(far_body, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(2.8, 0.0)))
	PhysicsServer2D.body_set_space(far_body, space)
	PhysicsServer2D.space_set_active(space, true)
	await tree.physics_frame
	var creation_ms := float(Time.get_ticks_usec() - start_creation) / 1000.0

	query.exclude_bodies = excluded_bodies
	var trials := mini(frames, 60)
	var errors := 0
	var begin := Time.get_ticks_usec()
	for i in range(trials):
		var collided := PhysicsServer2D.body_test_motion(mover, query, result)
		if not collided or result.get_collider_rid() != near_body or result.get_collision_safe_fraction() >= 0.2:
			errors += 1
	var query_ms := float(Time.get_ticks_usec() - begin) / 1000.0
	var near_fraction := result.get_collision_safe_fraction()

	excluded_bodies.append(near_body)
	query.exclude_bodies = excluded_bodies
	var far_hit := PhysicsServer2D.body_test_motion(mover, query, result)
	var far_fraction := result.get_collision_safe_fraction()
	var far_valid := (
		far_hit and result.get_collider_rid() == far_body
		and far_fraction > near_fraction
	)

	query.motion = Vector2.ZERO
	query.from = Transform2D.IDENTITY
	query.recovery_as_collision = true
	var static_hit := PhysicsServer2D.body_test_motion(mover, query, result)
	var stationary_valid := (
		not static_hit and result.get_travel().is_finite()
		and result.get_remainder().is_finite()
	)

	# All decoys now become valid broadphase candidates (>2048 shapes).
	# The nearest real collision must still win the exact narrowphase search.
	query.exclude_bodies = []
	query.motion = Vector2(4.0, 0.0)
	query.recovery_as_collision = false
	var dense_started := Time.get_ticks_usec()
	var dense_hit := PhysicsServer2D.body_test_motion(mover, query, result)
	var dense_query_ms := float(Time.get_ticks_usec() - dense_started) / 1000.0
	var dense_valid := (
		dense_hit and result.get_collider_rid() == near_body
		and result.get_collision_safe_fraction() < 0.2
	)

	# Multiple moving shapes must preserve the nearest hit even when BVH
	# traversal is repeated for each shape, without retaining a candidate array.
	query.exclude_bodies = []
	query.motion = Vector2(4.0, 0.0)
	query.recovery_as_collision = false
	PhysicsServer2D.body_add_shape(mover, circle, Transform2D(0.0, Vector2(0.0, 8.0)))
	var compound_hit := PhysicsServer2D.body_test_motion(mover, query, result)
	var compound_valid := (
		compound_hit and result.get_collider_rid() == near_body
		and result.get_collision_safe_fraction() < 0.2
	)

	PhysicsServer2D.space_set_active(space, false)
	for body in excluded_bodies:
		if body != near_body:
			PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(near_body)
	PhysicsServer2D.free_rid(far_body)
	PhysicsServer2D.free_rid(mover)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(space)

	if errors != 0 or not far_valid or not stationary_valid or not dense_valid or not compound_valid:
		return {"error": "2D motion exclusions, nearest obstacle or stationary sweep regressed",
				"failures": errors, "near_fraction": near_fraction, "far_fraction": far_fraction,
				"far_valid": far_valid, "stationary_valid": stationary_valid,
				"dense_valid": dense_valid, "compound_valid": compound_valid}
	return {"excluded_bodies": count, "queries": trials, "creation_ms": creation_ms,
			"motion_queries_ms": query_ms, "near_fraction": near_fraction, "far_fraction": far_fraction,
			"stationary_valid": true, "dense_candidate_count": count + 2,
			"dense_query_ms": dense_query_ms, "dense_nearest_hit_verified": dense_valid, "compound_nearest_hit_verified": compound_valid}
