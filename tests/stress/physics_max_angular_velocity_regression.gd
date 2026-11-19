extends SceneTree

# Compare unconstrained and capped dynamic spin in isolated 2D and 3D spaces.
# Run with GodotPhysics backends:
# godot --headless --path tests/stress --script res://physics_max_angular_velocity_regression.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result_2d: Dictionary = await _check_2d()
	var result_3d: Dictionary = await _check_3d()
	var passed: bool = bool(result_2d["passed"]) and bool(result_3d["passed"])
	print("MAX_ANGULAR_VELOCITY_RESULT:" + JSON.stringify({
		"passed": passed, "2d": result_2d, "3d": result_3d
	}))
	quit(0 if passed else 1)


func _check_2d() -> Dictionary:
	const SETTING = "physics/2d/solver/max_angular_velocity"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []

	for limit in [0.0, 12.0]:
		ProjectSettings.set_setting(SETTING, limit)
		var space := PhysicsServer2D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)

		var shape := PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(shape, 3.0)
		shapes.append(shape)

		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, -90.0)
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
		PhysicsServer2D.space_set_active(space, true)

	for frame in range(5):
		await physics_frame

	var raw: float = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
	var capped: float = PhysicsServer2D.body_get_state(bodies[1], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
	var passed: bool = raw < -50.0 and capped < 0.0 and absf(capped) <= 12.01 and absf(capped) > 0.1

	for space in spaces:
		PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for shape in shapes:
		PhysicsServer2D.free_rid(shape)
	for space in spaces:
		PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)
	return {"passed": passed, "unbounded_angular_speed": raw, "capped_angular_speed": capped}


func _check_3d() -> Dictionary:
	const SETTING = "physics/3d/solver/max_angular_velocity"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []

	for limit in [0.0, 12.0]:
		ProjectSettings.set_setting(SETTING, limit)
		var space := PhysicsServer3D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)

		var shape := PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(shape, 1.0)
		shapes.append(shape)

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 60.0, -80.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
		PhysicsServer3D.space_set_active(space, true)

	for frame in range(5):
		await physics_frame

	var raw: Vector3 = PhysicsServer3D.body_get_state(bodies[0], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var capped: Vector3 = PhysicsServer3D.body_get_state(bodies[1], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var passed: bool = (
		raw.length() > 50.0
		and capped.is_finite()
		and capped.length() <= 12.01
		and capped.length() > 0.1
		and capped.y > 0.0
		and capped.z < 0.0
	)

	for space in spaces:
		PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	for space in spaces:
		PhysicsServer3D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)
	return {"passed": passed, "unbounded_speed": raw.length(), "capped_speed": capped.length()}
