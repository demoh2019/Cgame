extends RefCounted
## BVH must reject body collision-exception pairs before allocating a constraint.
## Removing an exception must restore a contact without moving either body.

func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var mover := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(mover, PhysicsServer2D.BODY_MODE_KINEMATIC)
	PhysicsServer2D.body_add_shape(mover, shape)
	PhysicsServer2D.body_set_state(mover, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	PhysicsServer2D.body_set_space(mover, space)
	var count := 128 * mini(scale, 8)
	var obstacles: Array[RID] = []
	obstacles.resize(count)
	var begin := Time.get_ticks_usec()
	for i in range(count):
		var obstacle := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(obstacle, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(obstacle, shape)
		PhysicsServer2D.body_set_state(obstacle, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.25, 0.0)))
		PhysicsServer2D.body_set_space(obstacle, space)
		obstacles[i] = obstacle
	PhysicsServer2D.space_set_active(space, true)
	await tree.physics_frame
	await tree.physics_frame
	var creation_ms := float(Time.get_ticks_usec() - begin) / 1000.0
	var pairs_initial := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	# A BVH pair must be discarded even if the bodies never move.
	var exclude_start := Time.get_ticks_usec()
	for obstacle in obstacles:
		PhysicsServer2D.body_add_collision_exception(mover, obstacle)
	await tree.physics_frame
	await tree.physics_frame
	var exclude_ms := float(Time.get_ticks_usec() - exclude_start) / 1000.0
	var pairs_excluded := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	var restore_start := Time.get_ticks_usec()
	for obstacle in obstacles:
		PhysicsServer2D.body_remove_collision_exception(mover, obstacle)
	await tree.physics_frame
	await tree.physics_frame
	var restore_ms := float(Time.get_ticks_usec() - restore_start) / 1000.0
	var pairs_restored := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	# After repopulating, check the reverse direction of the exception.
	var reverse_start := Time.get_ticks_usec()
	for obstacle in obstacles:
		PhysicsServer2D.body_add_collision_exception(obstacle, mover)
	await tree.physics_frame
	await tree.physics_frame
	var pairs_reverse_excluded := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)
	for obstacle in obstacles:
		PhysicsServer2D.body_remove_collision_exception(obstacle, mover)
	await tree.physics_frame
	await tree.physics_frame
	var reverse_ms := float(Time.get_ticks_usec() - reverse_start) / 1000.0
	var pairs_reverse_restored := PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_COLLISION_PAIRS)

	PhysicsServer2D.space_set_active(space, false)
	for obstacle in obstacles:
		PhysicsServer2D.free_rid(obstacle)
	PhysicsServer2D.free_rid(mover)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)

	# Other active spaces, if any, add a constant baseline. Compare deltas.
	var passed := (
		pairs_initial >= count
		and pairs_excluded <= pairs_initial - count
		and pairs_restored >= pairs_excluded + count
		and pairs_reverse_excluded <= pairs_restored - count
		and pairs_reverse_restored >= pairs_reverse_excluded + count
	)
	if not passed:
		return {"error": "Stationary body exception BVH pairing did not update",
			"obstacles": count, "initial": pairs_initial, "excluded": pairs_excluded,
			"restored": pairs_restored, "reverse_excluded": pairs_reverse_excluded,
			"reverse_restored": pairs_reverse_restored}
	return {"obstacles": count, "initial_pairs": pairs_initial,
		"excluded_pairs": pairs_excluded, "restored_pairs": pairs_restored,
		"reverse_excluded_pairs": pairs_reverse_excluded,
		"reverse_restored_pairs": pairs_reverse_restored,
		"creation_ms": creation_ms, "exclude_ms": exclude_ms,
		"restore_ms": restore_ms, "reverse_ms": reverse_ms,
		"stationary_exception_filter_verified": true}
