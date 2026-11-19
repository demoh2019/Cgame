extends RefCounted
## Dense body-motion queries with more than 2048 user-excluded solid proxies.
## Also checks nearest sweep fractions and zero-displacement recovery stability.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var mover := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(mover, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_add_shape(mover, sphere)
	PhysicsServer3D.body_set_space(mover, space)

	var query := PhysicsTestMotionParameters3D.new()
	query.from = Transform3D.IDENTITY
	query.motion = Vector3(4.0, 0.0, 0.0)
	var result := PhysicsTestMotionResult3D.new()

	# Place all decoys on the sweep, not in a distant part of the BVH.
	# Their layers match the moving body; only exclude_bodies filters them.
	var excluded_bodies: Array[RID] = []
	var count := 2048 + 128 * mini(scale, 8)
	excluded_bodies.resize(count)
	var start_creation := Time.get_ticks_usec()
	for i in range(count):
		var decoy := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(decoy, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(decoy, sphere)
		PhysicsServer3D.body_set_state(decoy, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(1.8, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(decoy, space)
		excluded_bodies[i] = decoy

	# Create actual obstacles after decoys, so the broadphase cannot assume
	# the first 2048 unfiltered candidates are useful.
	var near_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(near_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(near_body, sphere)
	PhysicsServer3D.body_set_state(near_body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(1.4, 0.0, 0.0)))
	PhysicsServer3D.body_set_space(near_body, space)

	var far_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(far_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(far_body, sphere)
	PhysicsServer3D.body_set_state(far_body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(2.8, 0.0, 0.0)))
	PhysicsServer3D.body_set_space(far_body, space)
	PhysicsServer3D.space_set_active(space, true)
	await tree.physics_frame
	var creation_ms := float(Time.get_ticks_usec() - start_creation) / 1000.0

	query.exclude_bodies = excluded_bodies
	var trials := mini(frames, 60)
	var errors := 0
	var begin := Time.get_ticks_usec()
	for i in range(trials):
		var collided := PhysicsServer3D.body_test_motion(mover, query, result)
		if not collided or result.get_collision_count() < 1:
			errors += 1
		elif result.get_collider_rid() != near_body or result.get_collision_safe_fraction() >= 0.2:
			errors += 1
	var query_ms := float(Time.get_ticks_usec() - begin) / 1000.0
	var near_fraction := result.get_collision_safe_fraction()

	# Removing the nearest collider with an explicit exclusion must expose
	# the farther solid body, not thousands of excluded broadphase proxies.
	excluded_bodies.append(near_body)
	query.exclude_bodies = excluded_bodies
	var far_hit := PhysicsServer3D.body_test_motion(mover, query, result)
	var far_fraction := result.get_collision_safe_fraction()
	var far_valid := (
		far_hit and result.get_collision_count() > 0
		and result.get_collider_rid() == far_body and far_fraction > near_fraction
	)

	# A stationary sweep must not normalize a zero-length vector to NaNs.
	query.motion = Vector3.ZERO
	query.from = Transform3D.IDENTITY
	query.recovery_as_collision = true
	var static_hit := PhysicsServer3D.body_test_motion(mover, query, result)
	var stationary_valid := (
		not static_hit and result.get_travel().is_finite()
		and result.get_remainder().is_finite()
	)

	PhysicsServer3D.space_set_active(space, false)
	for body in excluded_bodies:
		if body != near_body:
			PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(near_body)
	PhysicsServer3D.free_rid(far_body)
	PhysicsServer3D.free_rid(mover)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)

	if errors != 0 or not far_valid or not stationary_valid:
		return {"error": "3D motion exclusions, nearest obstacle or stationary sweep regressed",
				"failures": errors, "near_fraction": near_fraction, "far_fraction": far_fraction,
				"far_valid": far_valid, "stationary_valid": stationary_valid}
	return {"excluded_bodies": count, "queries": trials, "creation_ms": creation_ms,
			"motion_queries_ms": query_ms, "near_fraction": near_fraction, "far_fraction": far_fraction,
			"stationary_valid": true}
