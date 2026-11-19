# Shape cast must find the nearest obstacle even after a preceding hit
# shrinks the possible TOI region. The far objects exercise the clipped
# AABB rejection before expensive SAT/GJK narrowphase.
# Run: --headless --path tests/stress --script res://physics_shapecast_clipped_aabb_regression.gd
extends SceneTree

const FAR_COUNT := 4096
const DISTANCE := 100.0
const REPEATS := 32


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var two: Dictionary = await _check_2d()
	var three: Dictionary = await _check_3d()
	if two.has("error") or three.has("error"):
		printerr("Clipped shape-cast AABB regression FAILED: 2D=", two, " 3D=", three)
		quit(1)
		return
	print("Clipped shape-cast AABB regression OK: 2D=", two, " 3D=", three)
	quit(0)


func _check_2d() -> Dictionary:
	var world_space := root.get_world_2d().space
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var bodies: Array[RID] = []
	for x in [2.5, 4.0]:
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(x, 0)))
		PhysicsServer2D.body_set_space(body, world_space)
		bodies.append(body)
	for i in range(FAR_COUNT):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(20.0 + float(i) * 0.015, 0)))
		PhysicsServer2D.body_set_space(body, world_space)
		bodies.append(body)
	await physics_frame
	await process_frame

	var state := root.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape_rid = shape
	params.transform = Transform2D.IDENTITY
	params.motion = Vector2(DISTANCE, 0)
	params.collision_mask = 1

	var begin := Time.get_ticks_usec()
	var wrong := 0
	var first_safe := -1.0
	for _i in range(REPEATS):
		var result := state.cast_motion(params)
		if result.size() != 2 or result[0] <= 0.0 or result[0] >= 0.025 or result[1] < result[0] or result[1] >= 0.05:
			wrong += 1
		elif first_safe < 0.0:
			first_safe = result[0]
	var time_us := Time.get_ticks_usec() - begin

	params.exclude = [bodies[0]]
	var after_exclusion := state.cast_motion(params)
	var second_ok := after_exclusion.size() == 2 and after_exclusion[0] > first_safe and after_exclusion[0] < 0.04
	params.exclude = []
	params.collision_mask = 2
	var masked := state.cast_motion(params)
	var masked_ok := masked.size() == 2 and is_equal_approx(masked[0], 1.0) and is_equal_approx(masked[1], 1.0)

	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)

	if wrong != 0 or not second_ok or not masked_ok:
		return {"error": "2D clipped cast missed the nearest hit or violated filtering",
				"wrong": wrong, "first": first_safe, "second": after_exclusion, "mask": masked_ok}
	return {"bodies": FAR_COUNT + 2, "casts": REPEATS + 2, "time_us": time_us,
			"first_safe": first_safe, "second_safe": after_exclusion[0]}


func _check_3d() -> Dictionary:
	var world_space := root.get_world_3d().space
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var bodies: Array[RID] = []
	for x in [2.5, 4.0]:
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(x, 0, 0)))
		PhysicsServer3D.body_set_space(body, world_space)
		bodies.append(body)
	for i in range(FAR_COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(20.0 + float(i) * 0.015, 0, 0)))
		PhysicsServer3D.body_set_space(body, world_space)
		bodies.append(body)
	await physics_frame
	await process_frame

	var state := root.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape_rid = shape
	params.transform = Transform3D.IDENTITY
	params.motion = Vector3(DISTANCE, 0, 0)
	params.collision_mask = 1

	var begin := Time.get_ticks_usec()
	var wrong := 0
	var first_safe := -1.0
	for _i in range(REPEATS):
		var result := state.cast_motion(params)
		if result.size() != 2 or result[0] <= 0.0 or result[0] >= 0.025 or result[1] < result[0] or result[1] >= 0.05:
			wrong += 1
		elif first_safe < 0.0:
			first_safe = result[0]
	var time_us := Time.get_ticks_usec() - begin

	params.exclude = [bodies[0]]
	var after_exclusion := state.cast_motion(params)
	var second_ok := after_exclusion.size() == 2 and after_exclusion[0] > first_safe and after_exclusion[0] < 0.04
	params.exclude = []
	params.collision_mask = 2
	var masked := state.cast_motion(params)
	var masked_ok := masked.size() == 2 and is_equal_approx(masked[0], 1.0) and is_equal_approx(masked[1], 1.0)

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)

	if wrong != 0 or not second_ok or not masked_ok:
		return {"error": "3D clipped cast missed the nearest hit or violated filtering",
				"wrong": wrong, "first": first_safe, "second": after_exclusion, "mask": masked_ok}
	return {"bodies": FAR_COUNT + 2, "casts": REPEATS + 2, "time_us": time_us,
			"first_safe": first_safe, "second_safe": after_exclusion[0]}
