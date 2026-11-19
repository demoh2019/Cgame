extends SceneTree

# Requires the built-in GodotPhysics3D backend, not Jolt.
# Run: godot --headless --path tests/stress --script res://physics_velocity_limit_3d_regression.gd

const SETTING := "physics/3d/solver/max_linear_velocity"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []

	for speed_limit in [0.0, 3.5]:
		ProjectSettings.set_setting(SETTING, speed_limit)
		var space := PhysicsServer3D.space_create()
		spaces.append(space)

		var shape := PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(shape, 0.5)
		shapes.append(shape)

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(2.0, -3.0, 6.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
		PhysicsServer3D.space_set_active(space, true)

	ProjectSettings.set_setting(SETTING, original)
	for i in range(4):
		await physics_frame

	var legacy: Vector3 = PhysicsServer3D.body_get_state(bodies[0], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var limited: Vector3 = PhysicsServer3D.body_get_state(bodies[1], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var passed := legacy.is_finite() and limited.is_finite()
	passed = passed and absf(legacy.length() - 7.0) < 0.05 and absf(limited.length() - 3.5) < 0.05

	PhysicsServer3D.body_apply_central_impulse(bodies[1], Vector3(100.0, 200.0, 300.0))
	for i in range(4):
		await physics_frame
	var after_impulse: Vector3 = PhysicsServer3D.body_get_state(bodies[1], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	passed = passed and after_impulse.is_finite() and absf(after_impulse.length() - 3.5) < 0.05

	for space in spaces:
		PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	for space in spaces:
		PhysicsServer3D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)

	print("PHYSICS_3D_VELOCITY_LIMIT_RESULT:" + JSON.stringify({
		"passed": passed, "legacy_speed": legacy.length(),
		"limited_speed": limited.length(), "after_impulse_speed": after_impulse.length()
	}))
	quit(0 if passed else 1)
