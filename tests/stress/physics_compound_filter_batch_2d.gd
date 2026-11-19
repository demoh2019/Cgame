extends RefCounted
## Compound-body batch regression: every local shape changes its pairing
## eligibility when collision layers/masks change on stationary bodies.

func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.4)
	var mover := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(mover, PhysicsServer2D.BODY_MODE_KINEMATIC)
	PhysicsServer2D.body_set_state(mover, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	var count := 32 * mini(scale, 8)
	var obstacles: Array[RID] = []
	obstacles.resize(count)
	var started := Time.get_ticks_usec()
	for i in range(count):
		var position := float(i) * 3.0
		PhysicsServer2D.body_add_shape(mover, shape, Transform2D(0.0, Vector2(position, 0.0)))
		var obstacle := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(obstacle, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(obstacle, shape)
		PhysicsServer2D.body_set_collision_mask(obstacle, 0)
		PhysicsServer2D.body_set_state(obstacle, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(position, 0.0)))
		PhysicsServer2D.body_set_space(obstacle, space)
		obstacles[i] = obstacle
	PhysicsServer2D.body_set_space(mover, space)
	PhysicsServer2D.space_set_active(space, true)
	await tree.physics_frame
	await tree.physics_frame
	var construction_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var original_pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	# Mask toggles on a stationary body with dozens or hundreds of local
	# shapes should create exactly one pair for each corresponding obstacle.
	var mask_mismatches := 0
	var mask_updates_us := 0
	var phases := mini(maxi(frames / 20, 2), 8)
	for phase in range(phases):
		var mask := 0 if phase % 2 == 0 else 1
		var tick := Time.get_ticks_usec()
		PhysicsServer2D.body_set_collision_mask(mover, mask)
		mask_updates_us += Time.get_ticks_usec() - tick
		await tree.physics_frame
		await tree.physics_frame
		var pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)
		if pairs != (0 if mask == 0 else count):
			mask_mismatches += 1

	# Exercise collision_layer independently: the opposing body must be
	# allowed to initiate contact when the mover's mask is zero.
	for obstacle in obstacles:
		PhysicsServer2D.body_set_collision_mask(obstacle, 1)
	PhysicsServer2D.body_set_collision_mask(mover, 0)
	await tree.physics_frame
	await tree.physics_frame
	var reverse_mask_pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)
	var layer_started := Time.get_ticks_usec()
	PhysicsServer2D.body_set_collision_layer(mover, 0)
	var layer_off_us := Time.get_ticks_usec() - layer_started
	await tree.physics_frame
	await tree.physics_frame
	var layer_off_pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)
	layer_started = Time.get_ticks_usec()
	PhysicsServer2D.body_set_collision_layer(mover, 1)
	var layer_on_us := Time.get_ticks_usec() - layer_started
	await tree.physics_frame
	await tree.physics_frame
	var layer_on_pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	# Collision exceptions also need to refresh all proxies for this
	# compound body; no movement is allowed to hide missing rechecks.
	var exception_started := Time.get_ticks_usec()
	PhysicsServer2D.body_add_collision_exception(mover, obstacles[0])
	var exception_add_us := Time.get_ticks_usec() - exception_started
	await tree.physics_frame
	await tree.physics_frame
	var excluded_pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)
	exception_started = Time.get_ticks_usec()
	PhysicsServer2D.body_remove_collision_exception(mover, obstacles[0])
	var exception_remove_us := Time.get_ticks_usec() - exception_started
	await tree.physics_frame
	await tree.physics_frame
	var restored_pairs := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(mover)
	for obstacle in obstacles:
		PhysicsServer2D.free_rid(obstacle)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)

	var correct := (
		original_pairs == count and mask_mismatches == 0
		and reverse_mask_pairs == count and layer_off_pairs == 0
		and layer_on_pairs == count and excluded_pairs == count - 1
		and restored_pairs == count
	)
	if not correct:
		return {"error": "Compound BVH batch missed stationary pair filter changes",
			"shapes": count, "initial": original_pairs, "mask_mismatches": mask_mismatches,
			"reverse_mask_pairs": reverse_mask_pairs, "layer_off_pairs": layer_off_pairs,
			"layer_on_pairs": layer_on_pairs, "excluded_pairs": excluded_pairs,
			"restored_pairs": restored_pairs}
	return {"shapes": count, "stationary_filter_phases": phases,
		"construction_ms": construction_ms,
		"mask_updates_ms": float(mask_updates_us) / 1000.0,
		"layer_updates_ms": float(layer_off_us + layer_on_us) / 1000.0,
		"exception_updates_ms": float(exception_add_us + exception_remove_us) / 1000.0,
		"compound_filter_batch_verified": true}
