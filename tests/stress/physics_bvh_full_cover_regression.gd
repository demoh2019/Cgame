# Verifies streamed AABB queries with fully covered BVH subtrees.
# Run: godot --headless --path tests/stress \
#    --script res://physics_bvh_full_cover_regression.gd
extends SceneTree

const SIDE := 64
const COUNT := SIDE * SIDE
const PARTIAL_EXPECTED := 30 * 30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result_2d: Dictionary = await _test_2d()
	var result_3d: Dictionary = await _test_3d()
	if result_2d.has("error") or result_3d.has("error"):
		printerr("BVH full-cover regression FAILED: 2D=", result_2d, " 3D=", result_3d)
		quit(1)
		return
	print("BVH full-cover regression OK: 2D=", result_2d, " 3D=", result_3d)
	quit(0)


func _test_2d() -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var sphere := PhysicsServer2D.circle_shape_create()
	var full_box := PhysicsServer2D.rectangle_shape_create()
	var partial_box := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(sphere, 0.25)
	PhysicsServer2D.shape_set_data(full_box, Vector2(100, 100))
	PhysicsServer2D.shape_set_data(partial_box, Vector2(30, 30))

	var bodies: Array[RID] = []
	for i in range(COUNT):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, sphere)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2((i % SIDE) * 2 - 63, floori(float(i) / float(SIDE)) * 2 - 63)))
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame

	var state := PhysicsServer2D.space_get_direct_state(space)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape_rid = full_box
	query.collision_mask = 1
	var before := Time.get_ticks_usec()
	var full := state.intersect_shape(query, COUNT)
	var full_us := Time.get_ticks_usec() - before

	query.shape_rid = partial_box
	before = Time.get_ticks_usec()
	var partial := state.intersect_shape(query, COUNT)
	var partial_us := Time.get_ticks_usec() - before

	query.shape_rid = full_box
	var early := state.intersect_shape(query, 3)
	query.collision_mask = 2
	var masked := state.intersect_shape(query, COUNT)
	var passed := full.size() == COUNT and partial.size() == PARTIAL_EXPECTED and early.size() == 3 and masked.is_empty()

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(sphere)
	PhysicsServer2D.free_rid(full_box)
	PhysicsServer2D.free_rid(partial_box)
	PhysicsServer2D.free_rid(space)

	if not passed:
		return {"error": "2D missing or extra BVH AABB candidates", "full": full.size(), "partial": partial.size(), "early": early.size(), "masked": masked.size()}
	return {"proxies": COUNT, "full_query_us": full_us, "partial_query_us": partial_us}


func _test_3d() -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	var full_box := PhysicsServer3D.box_shape_create()
	var partial_box := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.25)
	PhysicsServer3D.shape_set_data(full_box, Vector3(100, 100, 100))
	PhysicsServer3D.shape_set_data(partial_box, Vector3(30, 30, 3))

	var bodies: Array[RID] = []
	for i in range(COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, sphere)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3((i % SIDE) * 2 - 63, floori(float(i) / float(SIDE)) * 2 - 63, 0)))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
	PhysicsServer3D.space_set_active(space, true)
	await physics_frame

	var state := PhysicsServer3D.space_get_direct_state(space)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape_rid = full_box
	query.collision_mask = 1
	var before := Time.get_ticks_usec()
	var full := state.intersect_shape(query, COUNT)
	var full_us := Time.get_ticks_usec() - before

	query.shape_rid = partial_box
	before = Time.get_ticks_usec()
	var partial := state.intersect_shape(query, COUNT)
	var partial_us := Time.get_ticks_usec() - before

	query.shape_rid = full_box
	var early := state.intersect_shape(query, 3)
	query.collision_mask = 2
	var masked := state.intersect_shape(query, COUNT)
	var passed := full.size() == COUNT and partial.size() == PARTIAL_EXPECTED and early.size() == 3 and masked.is_empty()

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(full_box)
	PhysicsServer3D.free_rid(partial_box)
	PhysicsServer3D.free_rid(space)

	if not passed:
		return {"error": "3D missing or extra BVH AABB candidates", "full": full.size(), "partial": partial.size(), "early": early.size(), "masked": masked.size()}
	return {"proxies": COUNT, "full_query_us": full_us, "partial_query_us": partial_us}
