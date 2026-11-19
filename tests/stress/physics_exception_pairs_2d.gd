extends RefCounted
## BVH must reject body collision-exception pairs before allocating a constraint.
## Removing an exception must restore a contact without moving either body.

func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var server := PhysicsServer2D
	var space := server.space_create()
	var shape := server.circle_shape_create()
	server.shape_set_data(shape, 0.5)
	var mover := server.body_create()
	server.body_set_mode(mover, server.BODY_MODE_KINEMATIC)
	server.body_add_shape(mover, shape)
	server.body_set_state(mover, server.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	server.body_set_space(mover, space)
	var count := 128 * mini(scale, 8)
	var obstacles: Array[RID] = []
	obstacles.resize(count)
	var begin := Time.get_ticks_usec()
	for i in range(count):
		var obstacle := server.body_create()
		server.body_set_mode(obstacle, server.BODY_MODE_STATIC)
		server.body_add_shape(obstacle, shape)
		server.body_set_state(obstacle, server.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.25, 0.0)))
		server.body_set_space(obstacle, space)
		obstacles[i] = obstacle
	server.space_set_active(space, true)
	await tree.physics_frame
	await tree.physics_frame
	var creation_ms := float(Time.get_ticks_usec() - begin) / 1000.0
	var pairs_initial := server.get_process_info(server.INFO_COLLISION_PAIRS)

	# A BVH pair must be discarded even if the bodies never move.
	var exclude_start := Time.get_ticks_usec()
	for obstacle in obstacles:
		server.body_add_collision_exception(mover, obstacle)
	await tree.physics_frame
	await tree.physics_frame
	var exclude_ms := float(Time.get_ticks_usec() - exclude_start) / 1000.0
	var pairs_excluded := server.get_process_info(server.INFO_COLLISION_PAIRS)

	var restore_start := Time.get_ticks_usec()
	for obstacle in obstacles:
		server.body_remove_collision_exception(mover, obstacle)
	await tree.physics_frame
	await tree.physics_frame
	var restore_ms := float(Time.get_ticks_usec() - restore_start) / 1000.0
	var pairs_restored := server.get_process_info(server.INFO_COLLISION_PAIRS)

	# After repopulating, check the reverse direction of the exception.
	var reverse_start := Time.get_ticks_usec()
	for obstacle in obstacles:
		server.body_add_collision_exception(obstacle, mover)
	await tree.physics_frame
	await tree.physics_frame
	var pairs_reverse_excluded := server.get_process_info(server.INFO_COLLISION_PAIRS)
	for obstacle in obstacles:
		server.body_remove_collision_exception(obstacle, mover)
	await tree.physics_frame
	await tree.physics_frame
	var reverse_ms := float(Time.get_ticks_usec() - reverse_start) / 1000.0
	var pairs_reverse_restored := server.get_process_info(server.INFO_COLLISION_PAIRS)

	server.space_set_active(space, false)
	for obstacle in obstacles:
		server.free_rid(obstacle)
	server.free_rid(mover)
	server.free_rid(shape)
	server.free_rid(space)

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
