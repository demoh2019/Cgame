# Point queries must find valid collisions after >2048 excluded/masked proxies.
# Run with --headless --path tests/stress --script res://physics_point_query_overflow_regression.gd
extends SceneTree

const FILTERED_BODIES := 4096


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result_2d: Dictionary = await _test_2d()
	var result_3d: Dictionary = await _test_3d()
	if result_2d.has("error") or result_3d.has("error"):
		printerr("Point-query overflow regression failed: 2D=", result_2d, " 3D=", result_3d)
		quit(1)
		return
	print("Point-query overflow regression passed: 2D=", result_2d, " 3D=", result_3d)
	quit(0)


func _test_2d() -> Dictionary:
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 1.0)
	var bodies: Array[RID] = []
	var world_space := root.get_world_2d().space
	for i in range(FILTERED_BODIES + 1):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2.ZERO))
		PhysicsServer2D.body_set_collision_layer(body, 2 if i == FILTERED_BODIES else 1)
		PhysicsServer2D.body_set_space(body, world_space)
		bodies.append(body)

	await physics_frame
	await process_frame

	var query := PhysicsPointQueryParameters2D.new()
	query.position = Vector2.ZERO
	query.collision_mask = 2
	var state := root.get_world_2d().direct_space_state
	var started := Time.get_ticks_usec()
	var hits := state.intersect_point(query, 1)
	var query_us := Time.get_ticks_usec() - started
	var passed := hits.size() == 1 and hits[0].rid == bodies[FILTERED_BODIES]
	query.collision_mask = 4
	passed = passed and state.intersect_point(query, 1).is_empty()
	query.collision_mask = 2
	query.collide_with_bodies = false
	passed = passed and state.intersect_point(query, 1).is_empty()
	query.collide_with_bodies = true
	var excluded: Array[RID] = [bodies[FILTERED_BODIES]]
	query.exclude = excluded
	passed = passed and state.intersect_point(query, 1).is_empty()

	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)

	if not passed:
		return {"error": "2D valid point collider lost after 4096 filtered candidates", "query_us": query_us}
	return {"filtered": FILTERED_BODIES, "matching": 1, "query_us": query_us}


func _test_3d() -> Dictionary:
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 1.0)
	var bodies: Array[RID] = []
	var world_space := root.get_world_3d().space
	for i in range(FILTERED_BODIES + 1):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))
		PhysicsServer3D.body_set_collision_layer(body, 2 if i == FILTERED_BODIES else 1)
		PhysicsServer3D.body_set_space(body, world_space)
		bodies.append(body)

	await physics_frame
	await process_frame

	var query := PhysicsPointQueryParameters3D.new()
	query.position = Vector3.ZERO
	query.collision_mask = 2
	var state := root.get_world_3d().direct_space_state
	var started := Time.get_ticks_usec()
	var hits := state.intersect_point(query, 1)
	var query_us := Time.get_ticks_usec() - started
	var passed := hits.size() == 1 and hits[0].rid == bodies[FILTERED_BODIES]
	query.collision_mask = 4
	passed = passed and state.intersect_point(query, 1).is_empty()
	query.collision_mask = 2
	query.collide_with_bodies = false
	passed = passed and state.intersect_point(query, 1).is_empty()
	query.collide_with_bodies = true
	var excluded: Array[RID] = [bodies[FILTERED_BODIES]]
	query.exclude = excluded
	passed = passed and state.intersect_point(query, 1).is_empty()

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)

	if not passed:
		return {"error": "3D valid point collider lost after 4096 filtered candidates", "query_us": query_us}
	return {"filtered": FILTERED_BODIES, "matching": 1, "query_us": query_us}
