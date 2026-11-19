# Cached inverse transforms must preserve point-query results for rotated,
# translated, locally offset and subsequently moved shape instances.
# Run --headless --path tests/stress \
#     --script res://physics_point_cached_inverse_regression.gd
extends SceneTree

const COUNT := 256
const GRID := 16
const SPACING := 14.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var two: Dictionary = await _test_2d()
	var three: Dictionary = await _test_3d()
	if two.has("error") or three.has("error"):
		printerr("Cached point inverse regression FAILED: 2D=", two, " 3D=", three)
		quit(1)
		return
	print("Cached point inverse regression OK: 2D=", two, " 3D=", three)
	quit(0)


func _test_2d() -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var box := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(box, Vector2(1, 1))
	var local := Transform2D(0.38, Vector2(2.5, -1.75))
	var bodies: Array[RID] = []
	var world_points: Array[Vector2] = []
	for i in range(COUNT):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, box, local)
		var body_xform := Transform2D(float(i % 7) * 0.09,
				Vector2(float(i % GRID) * SPACING, float(floori(float(i) / float(GRID))) * SPACING))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, body_xform)
		PhysicsServer2D.body_set_collision_layer(body, 1)
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
		world_points.append((body_xform * local) * Vector2(0.15, -0.2))

	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await process_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	var state := PhysicsServer2D.space_get_direct_state(space)
	var begin := Time.get_ticks_usec()
	var failures := 0
	for i in range(COUNT):
		query.position = world_points[i]
		var hits := state.intersect_point(query, 2)
		if hits.size() != 1 or hits[0].rid != bodies[i]:
			failures += 1
	var elapsed := Time.get_ticks_usec() - begin

	query.position = world_points[0]
	query.collision_mask = 2
	var mask_ok := state.intersect_point(query, 1).is_empty()
	query.collision_mask = 1
	var excluded: Array[RID] = [bodies[0]]
	query.exclude = excluded
	var exclude_ok := state.intersect_point(query, 1).is_empty()
	query.exclude = []

	var moved_xform := Transform2D(0.63, Vector2(-40, -40))
	var new_local := Transform2D(-0.47, Vector2(3.0, 1.5))
	PhysicsServer2D.body_set_shape_transform(bodies[0], 0, new_local)
	PhysicsServer2D.body_set_state(bodies[0], PhysicsServer2D.BODY_STATE_TRANSFORM, moved_xform)
	await physics_frame
	await process_frame
	query.position = (moved_xform * new_local) * Vector2.ZERO
	var moved_hits := state.intersect_point(query, 1)
	var move_ok := moved_hits.size() == 1 and moved_hits[0].rid == bodies[0]
	query.position = world_points[0]
	var old_position_empty := state.intersect_point(query, 1).is_empty()

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(box)
	PhysicsServer2D.free_rid(space)

	if failures != 0 or not mask_ok or not exclude_ok or not move_ok or not old_position_empty:
		return {"error": "2D cached point inverse changed hit results", "failures": failures,
				"mask": mask_ok, "exclude": exclude_ok, "moved": move_ok, "old_empty": old_position_empty}
	return {"bodies": COUNT, "query_us": elapsed, "moved_and_updated": true}


func _test_3d() -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var box := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box, Vector3(1, 1, 1))
	var local := Transform3D(Basis(Vector3.RIGHT, 0.38), Vector3(2.5, -1.75, 0.4))
	var bodies: Array[RID] = []
	var world_points: Array[Vector3] = []
	for i in range(COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, box, local)
		var body_xform := Transform3D(Basis(Vector3.UP, float(i % 7) * 0.09),
				Vector3(float(i % GRID) * SPACING, 0.0, float(floori(float(i) / float(GRID))) * SPACING))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, body_xform)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
		world_points.append((body_xform * local) * Vector3(0.15, -0.2, 0.13))

	PhysicsServer3D.space_set_active(space, true)
	await physics_frame
	await process_frame
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = 1
	var state := PhysicsServer3D.space_get_direct_state(space)
	var begin := Time.get_ticks_usec()
	var failures := 0
	for i in range(COUNT):
		query.position = world_points[i]
		var hits := state.intersect_point(query, 2)
		if hits.size() != 1 or hits[0].rid != bodies[i]:
			failures += 1
	var elapsed := Time.get_ticks_usec() - begin

	query.position = world_points[0]
	query.collision_mask = 2
	var mask_ok := state.intersect_point(query, 1).is_empty()
	query.collision_mask = 1
	var excluded: Array[RID] = [bodies[0]]
	query.exclude = excluded
	var exclude_ok := state.intersect_point(query, 1).is_empty()
	query.exclude = []

	var moved_xform := Transform3D(Basis(Vector3.UP, 0.63), Vector3(-40, 3, -40))
	var new_local := Transform3D(Basis(Vector3.RIGHT, -0.47), Vector3(3.0, 1.5, 0.8))
	PhysicsServer3D.body_set_shape_transform(bodies[0], 0, new_local)
	PhysicsServer3D.body_set_state(bodies[0], PhysicsServer3D.BODY_STATE_TRANSFORM, moved_xform)
	await physics_frame
	await process_frame
	query.position = (moved_xform * new_local) * Vector3.ZERO
	var moved_hits := state.intersect_point(query, 1)
	var move_ok := moved_hits.size() == 1 and moved_hits[0].rid == bodies[0]
	query.position = world_points[0]
	var old_position_empty := state.intersect_point(query, 1).is_empty()

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(box)
	PhysicsServer3D.free_rid(space)

	if failures != 0 or not mask_ok or not exclude_ok or not move_ok or not old_position_empty:
		return {"error": "3D cached point inverse changed hit results", "failures": failures,
				"mask": mask_ok, "exclude": exclude_ok, "moved": move_ok, "old_empty": old_position_empty}
	return {"bodies": COUNT, "query_us": elapsed, "moved_and_updated": true}
