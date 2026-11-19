extends SceneTree

# Low-level GodotPhysics regression for Box2D-style geometric-mean friction.
# Runs legacy minimum and geometric-mean spaces side by side, without nodes.
# Run: godot --headless --path tests/stress --script res://physics_friction_mix_regression.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result_2d: Dictionary = await _compare_friction_2d()
	var result_3d: Dictionary = await _compare_friction_3d()
	var ok: bool = bool(result_2d.get("passed", false)) and bool(result_3d.get("passed", false))
	print("FRICTION_MIX_RESULT:" + JSON.stringify({"passed": ok, "2d": result_2d, "3d": result_3d}))
	quit(0 if ok else 1)


func _compare_friction_2d() -> Dictionary:
	const SETTING = "physics/2d/solver/friction_combine_mode"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []
	var movers: Array[RID] = []

	# Surface coefficients 1 and 0.25 mix to 0.25 (legacy) or 0.5
	# (geometric). Geometry is identical across the isolated spaces.
	for mode in [0, 1]:
		ProjectSettings.set_setting(SETTING, mode)
		var space := PhysicsServer2D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)

		var floor_shape := PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(floor_shape, Vector2(3000.0, 1.0))
		var circle_shape := PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(circle_shape, 0.5)
		shapes.append(floor_shape)
		shapes.append(circle_shape)

		var floor := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(floor, floor_shape)
		PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, 1.0)
		PhysicsServer2D.body_set_space(floor, space)
		bodies.append(floor)

		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_add_shape(body, circle_shape)
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID_LINEAR)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, 0.25)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_BOUNCE, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(0.0, -1.5)))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(150.0, 0.0))
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
		movers.append(body)
		PhysicsServer2D.space_set_active(space, true)

	# Allow gravity to create normal forces. Different mixing rules must
	# produce observably different horizontal speeds after contact.
	for frame in range(15):
		await physics_frame

	var legacy_velocity: Vector2 = PhysicsServer2D.body_get_state(movers[0], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var geometric_velocity: Vector2 = PhysicsServer2D.body_get_state(movers[1], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)

	for space in spaces:
		PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for shape in shapes:
		PhysicsServer2D.free_rid(shape)
	for space in spaces:
		PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)

	var difference: float = legacy_velocity.x - geometric_velocity.x
	return {"passed": legacy_velocity.is_finite() and geometric_velocity.is_finite() and difference > 3.0,
			"legacy_x": legacy_velocity.x, "geometric_x": geometric_velocity.x, "difference": difference}


func _compare_friction_3d() -> Dictionary:
	const SETTING = "physics/3d/solver/friction_combine_mode"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []
	var movers: Array[RID] = []

	for mode in [0, 1]:
		ProjectSettings.set_setting(SETTING, mode)
		var space := PhysicsServer3D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)

		var floor_shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(floor_shape, Vector3(300.0, 1.0, 300.0))
		var sphere_shape := PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(sphere_shape, 0.5)
		shapes.append(floor_shape)
		shapes.append(sphere_shape)

		var floor := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(floor, floor_shape)
		PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
		PhysicsServer3D.body_set_space(floor, space)
		bodies.append(floor)

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_add_shape(body, sphere_shape)
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID_LINEAR)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.25)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(0.0, 1.5, 0.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(8.0, 0.0, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
		movers.append(body)
		PhysicsServer3D.space_set_active(space, true)

	for frame in range(120):
		await physics_frame

	var legacy_velocity: Vector3 = PhysicsServer3D.body_get_state(movers[0], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var geometric_velocity: Vector3 = PhysicsServer3D.body_get_state(movers[1], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

	for space in spaces:
		PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	for space in spaces:
		PhysicsServer3D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)

	var difference: float = legacy_velocity.x - geometric_velocity.x
	return {"passed": legacy_velocity.is_finite() and geometric_velocity.is_finite() and difference > 0.2,
			"legacy_x": legacy_velocity.x, "geometric_x": geometric_velocity.x, "difference": difference}
