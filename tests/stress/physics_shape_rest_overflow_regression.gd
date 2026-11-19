# Verify that intersect_shape and get_rest_info do not lose matches after
# 4096 overlapping but collision-layer-filtered broadphase candidates.
# Run: --headless --path tests/stress --script res://physics_shape_rest_overflow_regression.gd
extends SceneTree

const FILTERED_COUNT := 4096
const TARGET_OFFSET := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result_2d := await _check_2d()
	var result_3d := await _check_3d()
	if result_2d.has("error") or result_3d.has("error"):
		printerr("Physics shape/rest overflow regression failed: 2D=", result_2d, " 3D=", result_3d)
		quit(1)
		return
	print("Physics shape/rest overflow regression passed: 2D=", result_2d, " 3D=", result_3d)
	quit(0)


func _check_2d() -> Dictionary:
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 1.0)
	var bodies: Array[RID] = []
	var world_space := root.get_world_2d().space
	for i in range(FILTERED_COUNT + 1):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_collision_layer(body, 2 if i == FILTERED_COUNT else 1)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(TARGET_OFFSET, 0)))
		PhysicsServer2D.body_set_space(body, world_space)
		bodies.append(body)

	await physics_frame
	await process_frame
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape_rid = shape
	params.transform = Transform2D.IDENTITY
	params.collision_mask = 2
	var state := root.get_world_2d().direct_space_state
	var started := Time.get_ticks_usec()
	var hits := state.intersect_shape(params, 1)
	var rest := state.get_rest_info(params)
	var query_us := Time.get_ticks_usec() - started
	var ok := hits.size() == 1 and not rest.is_empty()
	if ok:
		ok = hits[0].rid == bodies[FILTERED_COUNT] and rest.rid == bodies[FILTERED_COUNT]
	params.collision_mask = 4
	ok = ok and state.intersect_shape(params, 1).is_empty() and state.get_rest_info(params).is_empty()
	params.collision_mask = 2
	params.collide_with_bodies = false
	ok = ok and state.intersect_shape(params, 1).is_empty() and state.get_rest_info(params).is_empty()
	params.collide_with_bodies = true
	params.exclude = [bodies[FILTERED_COUNT]]
	ok = ok and state.intersect_shape(params, 1).is_empty() and state.get_rest_info(params).is_empty()

	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	if not ok:
		return {"error": "2D filtered shape/rest hit missing or filter not honored", "query_us": query_us}
	return {"filtered": FILTERED_COUNT, "matches": 1, "query_us": query_us}


func _check_3d() -> Dictionary:
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 1.0)
	var bodies: Array[RID] = []
	var world_space := root.get_world_3d().space
	for i in range(FILTERED_COUNT + 1):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_collision_layer(body, 2 if i == FILTERED_COUNT else 1)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(TARGET_OFFSET, 0, 0)))
		PhysicsServer3D.body_set_space(body, world_space)
		bodies.append(body)

	await physics_frame
	await process_frame
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape_rid = shape
	params.transform = Transform3D.IDENTITY
	params.collision_mask = 2
	var state := root.get_world_3d().direct_space_state
	var started := Time.get_ticks_usec()
	var hits := state.intersect_shape(params, 1)
	var rest := state.get_rest_info(params)
	var query_us := Time.get_ticks_usec() - started
	var ok := hits.size() == 1 and not rest.is_empty()
	if ok:
		ok = hits[0].rid == bodies[FILTERED_COUNT] and rest.rid == bodies[FILTERED_COUNT]
	params.collision_mask = 4
	ok = ok and state.intersect_shape(params, 1).is_empty() and state.get_rest_info(params).is_empty()
	params.collision_mask = 2
	params.collide_with_bodies = false
	ok = ok and state.intersect_shape(params, 1).is_empty() and state.get_rest_info(params).is_empty()
	params.collide_with_bodies = true
	params.exclude = [bodies[FILTERED_COUNT]]
	ok = ok and state.intersect_shape(params, 1).is_empty() and state.get_rest_info(params).is_empty()

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	if not ok:
		return {"error": "3D filtered shape/rest hit missing or filter not honored", "query_us": query_us}
	return {"filtered": FILTERED_COUNT, "matches": 1, "query_us": query_us}
