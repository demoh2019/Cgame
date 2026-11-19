extends SceneTree

# Integration test for the opt-in Box2D-style speed limit in built-in GodotPhysics2D.
# Run: godot --headless --path tests/stress --script res://physics_velocity_limit_2d_regression.gd

const SETTING := "physics/2d/solver/max_linear_velocity"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []

	for speed_limit in [0.0, 100.0]:
		ProjectSettings.set_setting(SETTING, speed_limit)
		var space := PhysicsServer2D.space_create()
		spaces.append(space)

		var shape := PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(shape, 1.0)
		shapes.append(shape)

		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(300.0, 400.0))
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
		PhysicsServer2D.space_set_active(space, true)

	# Existing spaces retain their settings when the project setting changes.
	ProjectSettings.set_setting(SETTING, original)
	for i in range(3):
		await physics_frame

	var legacy_velocity: Vector2 = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var limited_velocity: Vector2 = PhysicsServer2D.body_get_state(bodies[1], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var initial_passed := absf(legacy_velocity.length() - 500.0) < 0.1 and absf(limited_velocity.length() - 100.0) < 0.1
	initial_passed = initial_passed and limited_velocity.is_finite() and legacy_velocity.is_finite()

	PhysicsServer2D.body_apply_central_impulse(bodies[1], Vector2(1000.0, 300.0))
	for i in range(3):
		await physics_frame
	var after_impulse: Vector2 = PhysicsServer2D.body_get_state(bodies[1], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var impulse_passed := after_impulse.is_finite() and absf(after_impulse.length() - 100.0) < 0.1

	for space in spaces:
		PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for shape in shapes:
		PhysicsServer2D.free_rid(shape)
	for space in spaces:
		PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)

	var passed := initial_passed and impulse_passed
	print("PHYSICS_2D_VELOCITY_LIMIT_RESULT:" + JSON.stringify({
		"passed": passed, "legacy_speed": legacy_velocity.length(),
		"limited_speed": limited_velocity.length(), "after_impulse_speed": after_impulse.length()
	}))
	quit(0 if passed else 1)
