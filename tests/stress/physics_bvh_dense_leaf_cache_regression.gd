# Dense BVH ray leaf regression: original entry must remain valid when a
# near exact hit clips the ray. Run with the GodotPhysics backend:
# --headless --path tests/stress --script res://physics_bvh_dense_leaf_cache_regression.gd
extends SceneTree

const COUNT := 96
const STEP := 2.5
const REPEATS := 80


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var two: Dictionary = await _test_2d()
	var three: Dictionary = await _test_3d()
	if two.has("error") or three.has("error"):
		printerr("Dense leaf ray cache FAILED: 2D=", two, ", 3D=", three)
		quit(1)
		return
	print("Dense leaf ray cache passed: 2D=", two, ", 3D=", three)
	quit(0)


func _test_2d() -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(shape, Vector2(0.3, 0.3))
	var bodies: Array[RID] = []
	for i in range(COUNT):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i) * STEP, 0.0)))
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await process_frame

	var state := PhysicsServer2D.space_get_direct_state(space)
	var query := PhysicsRayQueryParameters2D.new()
	query.from = Vector2(-4, 0)
	query.to = Vector2(COUNT * STEP + 4, 0)
	var miss_count := 0
	var begin := Time.get_ticks_usec()
	for _i in range(REPEATS):
		var hit := state.intersect_ray(query)
		if hit.is_empty() or hit.rid != bodies[0]:
			miss_count += 1
	var elapsed := Time.get_ticks_usec() - begin
	var excluded: Array[RID] = [bodies[0]]
	query.exclude = excluded
	var second := state.intersect_ray(query)
	var second_ok := not second.is_empty() and second.rid == bodies[1]
	query.exclude = []
	query.from = Vector2(COUNT * STEP + 4, 0)
	query.to = Vector2(-4, 0)
	var backwards := state.intersect_ray(query)
	var reverse_ok := not backwards.is_empty() and backwards.rid == bodies[COUNT - 1]
	query.collision_mask = 2
	var masked_ok := state.intersect_ray(query).is_empty()

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)

	if miss_count > 0 or not second_ok or not reverse_ok or not masked_ok:
		return {"error": "2D nearest/excluded/reverse/masked ray mismatch",
				"misses": miss_count, "second": second_ok, "reverse": reverse_ok, "mask": masked_ok}
	return {"bodies": COUNT, "queries": REPEATS + 3, "query_us": elapsed}


func _test_3d() -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(0.3, 0.3, 0.3))
	var bodies: Array[RID] = []
	for i in range(COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i) * STEP, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
	PhysicsServer3D.space_set_active(space, true)
	await physics_frame
	await process_frame

	var state := PhysicsServer3D.space_get_direct_state(space)
	var query := PhysicsRayQueryParameters3D.new()
	query.from = Vector3(-4, 0, 0)
	query.to = Vector3(COUNT * STEP + 4, 0, 0)
	var miss_count := 0
	var begin := Time.get_ticks_usec()
	for _i in range(REPEATS):
		var hit := state.intersect_ray(query)
		if hit.is_empty() or hit.rid != bodies[0]:
			miss_count += 1
	var elapsed := Time.get_ticks_usec() - begin
	var excluded: Array[RID] = [bodies[0]]
	query.exclude = excluded
	var second := state.intersect_ray(query)
	var second_ok := not second.is_empty() and second.rid == bodies[1]
	query.exclude = []
	query.from = Vector3(COUNT * STEP + 4, 0, 0)
	query.to = Vector3(-4, 0, 0)
	var backwards := state.intersect_ray(query)
	var reverse_ok := not backwards.is_empty() and backwards.rid == bodies[COUNT - 1]
	query.collision_mask = 2
	var masked_ok := state.intersect_ray(query).is_empty()

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	if miss_count > 0 or not second_ok or not reverse_ok or not masked_ok:
		return {"error": "3D nearest/excluded/reverse/masked ray mismatch",
				"misses": miss_count, "second": second_ok, "reverse": reverse_ok, "mask": masked_ok}
	return {"bodies": COUNT, "queries": REPEATS + 3, "query_us": elapsed}
