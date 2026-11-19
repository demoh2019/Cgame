extends SceneTree

# Headless GodotPhysics integration: space-local rigid speed caps in 2D/3D.
# Run: godot --headless --path tests/stress --script res://physics_max_linear_velocity_regression.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result_2d: Dictionary = await _check_2d()
	var result_3d: Dictionary = await _check_3d()
	var passed: bool = bool(result_2d["passed"]) and bool(result_3d["passed"])
	print("MAX_LINEAR_VELOCITY_RESULT:" + JSON.stringify({"passed": passed, "2d": result_2d, "3d": result_3d}))
	quit(0 if passed else 1)


func _check_2d() -> Dictionary:
	const SETTING = "physics/2d/solver/max_linear_velocity"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []

	for speed_cap in [0.0, 40.0]:
		ProjectSettings.set_setting(SETTING, speed_cap)
		var space := PhysicsServer2D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0.0)
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_LINEAR_DAMP, 0.0)

		var shape := PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(shape, 5.0)
		shapes.append(shape)

		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(300.0, 400.0))
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
		PhysicsServer2D.space_set_active(space, true)

	for frame in range(4):
		await physics_frame

	var baseline_velocity: Vector2 = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var capped_velocity: Vector2 = PhysicsServer2D.body_get_state(bodies[1], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var baseline: float = baseline_velocity.length()
	var capped: float = capped_velocity.length()
	var passed: bool = baseline > 200.0 and capped <= 40.01 and capped > 0.0 and capped_velocity.is_finite()

	for space in spaces:
		PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for shape in shapes:
		PhysicsServer2D.free_rid(shape)
	for space in spaces:
		PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)
	return {"passed": passed, "baseline_speed": baseline, "capped_speed": capped}


func _check_3d() -> Dictionary:
	const SETTING = "physics/3d/solver/max_linear_velocity"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []

	for speed_cap in [0.0, 40.0]:
		ProjectSettings.set_setting(SETTING, speed_cap)
		var space := PhysicsServer3D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_LINEAR_DAMP, 0.0)

		var shape := PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(shape, 1.0)
		shapes.append(shape)

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(300.0, 400.0, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
		PhysicsServer3D.space_set_active(space, true)

	for frame in range(4):
		await physics_frame

	var baseline_velocity: Vector3 = PhysicsServer3D.body_get_state(bodies[0], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var capped_velocity: Vector3 = PhysicsServer3D.body_get_state(bodies[1], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var baseline: float = baseline_velocity.length()
	var capped: float = capped_velocity.length()
	var passed: bool = baseline > 200.0 and capped <= 40.01 and capped > 0.0 and capped_velocity.is_finite()

	for space in spaces:
		PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	for space in spaces:
		PhysicsServer3D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)
	return {"passed": passed, "baseline_speed": baseline, "capped_speed": capped}
