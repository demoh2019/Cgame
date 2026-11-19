# Nearest-hit raycasts must remain correct with more than 2048 BVH candidates.
# Usage: godot --headless --path tests/stress --script res://physics_ray_overflow_regression.gd
extends SceneTree

const COUNT := 4096
const SPACING := 4.0
const RADIUS := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result_2d: Dictionary = await _test_2d()
	var result_3d: Dictionary = await _test_3d()
	if result_2d.has("error") or result_3d.has("error"):
		printerr("Ray overflow regression failed: 2D=", result_2d, " 3D=", result_3d)
		quit(1)
		return
	print("Ray overflow regression passed: 2D=", result_2d, " 3D=", result_3d)
	quit(0)


func _test_2d() -> Dictionary:
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, RADIUS)
	var world_space := root.get_world_2d().space
	var bodies: Array[RID] = []
	bodies.resize(COUNT)
	for i in range(COUNT):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i) * SPACING, 0.0)))
		PhysicsServer2D.body_set_collision_layer(body, 2 if i == 0 else 1)
		PhysicsServer2D.body_set_space(body, world_space)
		bodies[i] = body

	await physics_frame
	await process_frame
	var start := Vector2(-2.0, 0.0)
	var finish := Vector2(float(COUNT - 1) * SPACING + 2.0, 0.0)
	var state := root.get_world_2d().direct_space_state
	var all_query := PhysicsRayQueryParameters2D.create(start, finish)
	all_query.collision_mask = 3
	var first := state.intersect_ray(all_query)
	var masked_query := PhysicsRayQueryParameters2D.create(start, finish)
	masked_query.collision_mask = 1
	var second := state.intersect_ray(masked_query)
	var reverse_query := PhysicsRayQueryParameters2D.create(finish, start)
	reverse_query.collision_mask = 3
	var last := state.intersect_ray(reverse_query)

	var valid := not first.is_empty() and not second.is_empty() and not last.is_empty()
	if valid:
		valid = first.rid == bodies[0] and second.rid == bodies[1] and last.rid == bodies[COUNT - 1]
		valid = valid and absf(first.position.x + RADIUS) < 0.05
		valid = valid and absf(second.position.x - (SPACING - RADIUS)) < 0.05
		valid = valid and absf(last.position.x - (float(COUNT - 1) * SPACING + RADIUS)) < 0.05

	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	return {"bodies": COUNT, "correct": true} if valid else {"error": "2D nearest hit / collision mask incorrect after 4096 candidates"}


func _test_3d() -> Dictionary:
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, RADIUS)
	var world_space := root.get_world_3d().space
	var bodies: Array[RID] = []
	bodies.resize(COUNT)
	for i in range(COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i) * SPACING, 0.0, 0.0)))
		PhysicsServer3D.body_set_collision_layer(body, 2 if i == 0 else 1)
		PhysicsServer3D.body_set_space(body, world_space)
		bodies[i] = body

	await physics_frame
	await process_frame
	var start := Vector3(-2.0, 0.0, 0.0)
	var finish := Vector3(float(COUNT - 1) * SPACING + 2.0, 0.0, 0.0)
	var state := root.get_world_3d().direct_space_state
	var all_query := PhysicsRayQueryParameters3D.create(start, finish)
	all_query.collision_mask = 3
	var first := state.intersect_ray(all_query)
	var masked_query := PhysicsRayQueryParameters3D.create(start, finish)
	masked_query.collision_mask = 1
	var second := state.intersect_ray(masked_query)
	var reverse_query := PhysicsRayQueryParameters3D.create(finish, start)
	reverse_query.collision_mask = 3
	var last := state.intersect_ray(reverse_query)

	var valid := not first.is_empty() and not second.is_empty() and not last.is_empty()
	if valid:
		valid = first.rid == bodies[0] and second.rid == bodies[1] and last.rid == bodies[COUNT - 1]
		valid = valid and absf(first.position.x + RADIUS) < 0.05
		valid = valid and absf(second.position.x - (SPACING - RADIUS)) < 0.05
		valid = valid and absf(last.position.x - (float(COUNT - 1) * SPACING + RADIUS)) < 0.05

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	return {"bodies": COUNT, "correct": true} if valid else {"error": "3D nearest hit / collision mask incorrect after 4096 candidates"}
