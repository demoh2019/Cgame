# Regression for 2D/3D cached AABB broadphase updates.
# Run: godot --headless --path tests/stress --script res://physics_broadphase_aabb_cache_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space_2d := PhysicsServer2D.space_create()
	var shape_2d := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(shape_2d, Vector2(1.0, 1.0))
	var body_2d := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body_2d, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body_2d, shape_2d)
	var initial_2d := Transform2D(0.0, Vector2(-8.0, 0.0))
	PhysicsServer2D.body_set_state(body_2d, PhysicsServer2D.BODY_STATE_TRANSFORM, initial_2d)
	PhysicsServer2D.body_set_space(body_2d, space_2d)
	PhysicsServer2D.space_set_active(space_2d, true)

	var space_3d := PhysicsServer3D.space_create()
	var shape_3d := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape_3d, Vector3(1.0, 1.0, 1.0))
	var body_3d := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_3d, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body_3d, shape_3d)
	var initial_3d := Transform3D(Basis(), Vector3(-8.0, 0.0, 0.0))
	PhysicsServer3D.body_set_state(body_3d, PhysicsServer3D.BODY_STATE_TRANSFORM, initial_3d)
	PhysicsServer3D.body_set_space(body_3d, space_3d)
	PhysicsServer3D.space_set_active(space_3d, true)

	await physics_frame
	await physics_frame
	var state_2d: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space_2d)
	var state_3d: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space_3d)
	var failures := 0
	if state_2d == null or state_3d == null:
		printerr("FAIL: direct physics spaces are unavailable")
		failures += 1
	else:
		var ray_old_2d := PhysicsRayQueryParameters2D.create(Vector2(-11, 0), Vector2(-5, 0))
		var ray_old_3d := PhysicsRayQueryParameters3D.create(Vector3(-11, 0, 0), Vector3(-5, 0, 0))
		if state_2d.intersect_ray(ray_old_2d).is_empty() or state_3d.intersect_ray(ray_old_3d).is_empty():
			printerr("FAIL: initially registered 2D/3D broadphase proxies were not found")
			failures += 1

		# Reapply identical transforms. This must avoid redundant BVH moves
		# without causing the proxies to disappear from queries.
		for i in range(32):
			PhysicsServer2D.body_set_state(body_2d, PhysicsServer2D.BODY_STATE_TRANSFORM, initial_2d)
			PhysicsServer3D.body_set_state(body_3d, PhysicsServer3D.BODY_STATE_TRANSFORM, initial_3d)
			await physics_frame
		if state_2d.intersect_ray(ray_old_2d).is_empty() or state_3d.intersect_ray(ray_old_3d).is_empty():
			printerr("FAIL: unchanged-AABB fast path lost a 2D/3D proxy")
			failures += 1

		# A different AABB must always reach the tree.
		PhysicsServer2D.body_set_state(body_2d, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(8.0, 0.0)))
		PhysicsServer3D.body_set_state(body_3d, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(8.0, 0.0, 0.0)))
		await physics_frame
		await physics_frame

		var old_hit := state_2d.intersect_ray(ray_old_2d)
		var old_hit_3d := state_3d.intersect_ray(ray_old_3d)
		var ray_new_2d := PhysicsRayQueryParameters2D.create(Vector2(5, 0), Vector2(11, 0))
		var ray_new_3d := PhysicsRayQueryParameters3D.create(Vector3(5, 0, 0), Vector3(11, 0, 0))
		var new_hit := state_2d.intersect_ray(ray_new_2d)
		var new_hit_3d := state_3d.intersect_ray(ray_new_3d)
		if not old_hit.is_empty() or not old_hit_3d.is_empty() or new_hit.is_empty() or new_hit_3d.is_empty():
			printerr("FAIL: moving proxy did not update 2D and 3D ray queries")
			failures += 1

		# Changing shape dimensions without moving the body also changes
		# the bounding box, so the cache check must NOT swallow this update.
		PhysicsServer2D.shape_set_data(shape_2d, Vector2(2.0, 1.0))
		PhysicsServer3D.shape_set_data(shape_3d, Vector3(2.0, 1.0, 1.0))
		await physics_frame
		await physics_frame
		var bigger_2d := PhysicsRayQueryParameters2D.create(Vector2(5, 0), Vector2(6.7, 0))
		var bigger_3d := PhysicsRayQueryParameters3D.create(Vector3(5, 0, 0), Vector3(6.7, 0, 0))
		if state_2d.intersect_ray(bigger_2d).is_empty() or state_3d.intersect_ray(bigger_3d).is_empty():
			printerr("FAIL: changed shape extents did not update the cached AABB")
			failures += 1

	PhysicsServer2D.space_set_active(space_2d, false)
	PhysicsServer3D.space_set_active(space_3d, false)
	PhysicsServer2D.free_rid(body_2d)
	PhysicsServer3D.free_rid(body_3d)
	PhysicsServer2D.free_rid(shape_2d)
	PhysicsServer3D.free_rid(shape_3d)
	PhysicsServer2D.free_rid(space_2d)
	PhysicsServer3D.free_rid(space_3d)

	if failures == 0:
		print("2D/3D cached AABB regression passed.")
	else:
		printerr("2D/3D cached AABB regression: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
