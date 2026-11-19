# Kinematic sweep regression: 4096 filtered proxies must not hide the
# next obstacle, and repeated 3D candidates must start with the full sweep.
# Run with: --headless --path tests/stress \
#   --script res://physics_cast_motion_overflow_regression.gd
extends SceneTree

const FILTERED_COUNT := 4096
const SWEEP_DISTANCE := 10.0
const OBSTACLE_X := 4.0
const SHAPE_RADIUS := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result_2d: Dictionary = await _check_2d()
	var result_3d: Dictionary = await _check_3d()
	if result_2d.has("error") or result_3d.has("error"):
		printerr("Physics cast_motion overflow regression FAILED: 2D=", result_2d, " 3D=", result_3d)
		quit(1)
		return
	print("Physics cast_motion overflow regression OK: 2D=", result_2d, " 3D=", result_3d)
	quit(0)


func _check_2d() -> Dictionary:
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, SHAPE_RADIUS)
	var world_space := root.get_world_2d().space
	var bodies: Array[RID] = []
	for i in range(FILTERED_COUNT + 1):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_collision_layer(body, 2 if i == FILTERED_COUNT else 1)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(OBSTACLE_X, 0.0)))
		PhysicsServer2D.body_set_space(body, world_space)
		bodies.append(body)
	await physics_frame
	await process_frame

	var state := root.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape_rid = shape
	params.transform = Transform2D.IDENTITY
	params.motion = Vector2(SWEEP_DISTANCE, 0.0)
	params.collision_mask = 2

	var start_us := Time.get_ticks_usec()
	var result := state.cast_motion(params)
	var elapsed_us := Time.get_ticks_usec() - start_us
	var correct_hit := result.size() >= 2 and result[0] > 0.15 and result[0] < 0.45 and result[1] < 0.5
	var passed := correct_hit

	params.collision_mask = 4
	var no_hit := state.cast_motion(params)
	passed = passed and no_hit.size() >= 2 and is_equal_approx(no_hit[0], 1.0) and is_equal_approx(no_hit[1], 1.0)
	params.collision_mask = 2
	var excluded: Array[RID] = [bodies[FILTERED_COUNT]]
	params.exclude = excluded
	var excluded_hit := state.cast_motion(params)
	passed = passed and excluded_hit.size() >= 2 and is_equal_approx(excluded_hit[0], 1.0)
	params.exclude = []

	# The second matching obstacle is closer, regardless of BVH ordering.
	var near_body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(near_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(near_body, shape)
	PhysicsServer2D.body_set_collision_layer(near_body, 2)
	PhysicsServer2D.body_set_state(near_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(2.0, 0.0)))
	PhysicsServer2D.body_set_space(near_body, world_space)
	bodies.append(near_body)
	await physics_frame
	var near_hit := state.cast_motion(params)
	passed = passed and near_hit.size() >= 2 and near_hit[0] >= 0.0 and near_hit[0] < 0.2

	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	if not passed:
		return {"error": "2D cast_motion did not find the nearest filtered obstacle", "first_safe": result[0] if result.size() > 0 else -1, "near_safe": near_hit[0] if near_hit.size() > 0 else -1}
	return {"candidates": FILTERED_COUNT + 2, "first_safe": result[0], "near_safe": near_hit[0], "query_us": elapsed_us}


func _check_3d() -> Dictionary:
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, SHAPE_RADIUS)
	var world_space := root.get_world_3d().space
	var bodies: Array[RID] = []
	for i in range(FILTERED_COUNT + 1):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_collision_layer(body, 2 if i == FILTERED_COUNT else 1)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(OBSTACLE_X, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(body, world_space)
		bodies.append(body)
	await physics_frame
	await process_frame

	var state := root.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape_rid = shape
	params.transform = Transform3D.IDENTITY
	params.motion = Vector3(SWEEP_DISTANCE, 0.0, 0.0)
	params.collision_mask = 2

	var start_us := Time.get_ticks_usec()
	var result := state.cast_motion(params)
	var elapsed_us := Time.get_ticks_usec() - start_us
	var correct_hit := result.size() >= 2 and result[0] > 0.15 and result[0] < 0.45 and result[1] < 0.5
	var passed := correct_hit

	params.collision_mask = 4
	var no_hit := state.cast_motion(params)
	passed = passed and no_hit.size() >= 2 and is_equal_approx(no_hit[0], 1.0) and is_equal_approx(no_hit[1], 1.0)
	params.collision_mask = 2
	var excluded: Array[RID] = [bodies[FILTERED_COUNT]]
	params.exclude = excluded
	var excluded_hit := state.cast_motion(params)
	passed = passed and excluded_hit.size() >= 2 and is_equal_approx(excluded_hit[0], 1.0)
	params.exclude = []

	# Exercise sequential candidates: the binary-search motion fraction from
	# the previous candidate must not truncate the next candidate's sweep.
	var near_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(near_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(near_body, shape)
	PhysicsServer3D.body_set_collision_layer(near_body, 2)
	PhysicsServer3D.body_set_state(near_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(2.0, 0.0, 0.0)))
	PhysicsServer3D.body_set_space(near_body, world_space)
	bodies.append(near_body)
	await physics_frame
	var near_hit := state.cast_motion(params)
	passed = passed and near_hit.size() >= 2 and near_hit[0] >= 0.0 and near_hit[0] < 0.2

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	if not passed:
		return {"error": "3D cast_motion did not find the nearest filtered obstacle", "first_safe": result[0] if result.size() > 0 else -1, "near_safe": near_hit[0] if near_hit.size() > 0 else -1}
	return {"candidates": FILTERED_COUNT + 2, "first_safe": result[0], "near_safe": near_hit[0], "query_us": elapsed_us}
