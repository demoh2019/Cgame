extends RefCounted
## Dense dynamic/static BVH pair construction, filter toggling and reinsertion.
## Static bodies cannot collide with one another; all pairs involve one mover.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var obstacle_count := 2048 + 128 * mini(scale, 8)
	var obstacles: Array[RID] = []
	obstacles.resize(obstacle_count)
	var create_started := Time.get_ticks_usec()
	for i in range(obstacle_count):
		var obstacle := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(obstacle, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_mask(obstacle, 0)
		PhysicsServer3D.body_add_shape(obstacle, shape)
		PhysicsServer3D.body_set_state(obstacle, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0.2, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(obstacle, space)
		obstacles[i] = obstacle

	# Adding this last proxy triggers a BVH query containing every obstacle.
	var mover := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(mover, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_add_shape(mover, shape)
	PhysicsServer3D.body_set_state(mover, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	PhysicsServer3D.body_set_space(mover, space)
	PhysicsServer3D.space_set_active(space, true)
	await tree.physics_frame
	await tree.physics_frame
	var creation_ms := float(Time.get_ticks_usec() - create_started) / 1000.0
	var initial_pairs := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS)

	# Unlike the AABB, neither object's transform ever changes during these
	# filter toggles. BVH pairs must be removed and reconstructed correctly.
	var failures := 0
	var toggle_count := mini(8, maxi(2, int(frames / 20)))
	var toggle_started := Time.get_ticks_usec()
	for i in range(toggle_count):
		var new_mask := 0 if i % 2 == 0 else 1
		PhysicsServer3D.body_set_collision_mask(mover, new_mask)
		await tree.physics_frame
		await tree.physics_frame
		var current_pairs := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS)
		if current_pairs != (obstacle_count if new_mask != 0 else 0):
			failures += 1
	var toggle_ms := float(Time.get_ticks_usec() - toggle_started) / 1000.0

	# Force a large pair teardown/rebuild with unchanged shape geometry.
	PhysicsServer3D.body_set_collision_mask(mover, 1)
	await tree.physics_frame
	await tree.physics_frame
	var removal_started := Time.get_ticks_usec()
	PhysicsServer3D.body_set_space(mover, RID())
	await tree.physics_frame
	await tree.physics_frame
	var removed_pairs := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS)
	PhysicsServer3D.body_set_space(mover, space)
	await tree.physics_frame
	await tree.physics_frame
	var rebuilt_pairs := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS)
	var reinsertion_ms := float(Time.get_ticks_usec() - removal_started) / 1000.0

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(mover)
	for obstacle in obstacles:
		PhysicsServer3D.free_rid(obstacle)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	var valid := (
		initial_pairs == obstacle_count
		and failures == 0
		and removed_pairs == 0
		and rebuilt_pairs == obstacle_count
	)
	if not valid:
		return {"error": "Dense BVH pair creation, filter toggles or reinsertion failed",
			"objects": obstacle_count + 1, "initial_pairs": initial_pairs,
			"toggle_failures": failures, "removed_pairs": removed_pairs,
			"rebuilt_pairs": rebuilt_pairs}
	return {"objects": obstacle_count + 1, "candidate_pairs": obstacle_count,
		"creation_ms": creation_ms, "toggle_cycles": toggle_count,
		"toggle_ms": toggle_ms, "reinsertion_ms": reinsertion_ms,
		"pair_rebuild_verified": true}
