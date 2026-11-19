# Run with the built-in GodotPhysics3D backend:
# godot --headless --path tests/stress --script res://physics_gyroscopic_3d_regression.gd
extends SceneTree

const FRAMES := 240
const INITIAL_OMEGA := Vector3(3.0, 5.0, 7.0)
const INERTIA := Vector3(1.0, 2.0, 4.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original: Dictionary = await _run_case(false)
	var gyroscopic: Dictionary = await _run_case(true)
	print("GYROSCOPIC_3D_LEGACY:" + JSON.stringify(original))
	print("GYROSCOPIC_3D_ENABLED:" + JSON.stringify(gyroscopic))

	var valid := bool(original.get("finite", false)) and bool(gyroscopic.get("finite", false))
	valid = valid and float(original.get("angular_change", 1e10)) < 0.03
	valid = valid and float(gyroscopic.get("angular_change", 0.0)) > 0.05
	valid = valid and float(gyroscopic.get("max_momentum_error", 1e10)) < 0.03
	if valid:
		print("3D gyroscopic free-rotation regression passed.")
		quit(0)
	else:
		printerr("FAIL: 3D gyroscopic free-rotation regression")
		quit(1)


func _run_case(enabled: bool) -> Dictionary:
	const SETTING := "physics/3d/solver/gyroscopic_forces"
	var saved_setting: Variant = ProjectSettings.get_setting(SETTING, false)
	ProjectSettings.set_setting(SETTING, enabled)
	var space: RID = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(SETTING, saved_setting)

	var shape: RID = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(1, 2, 3))
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_INERTIA, INERTIA)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(0, 10, 0)))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, INITIAL_OMEGA)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.space_set_active(space, true)

	var initial_momentum := Vector3(INERTIA.x * INITIAL_OMEGA.x,
			INERTIA.y * INITIAL_OMEGA.y, INERTIA.z * INITIAL_OMEGA.z).length()
	var max_momentum_error := 0.0
	var angular_change := 0.0
	var finite := true
	for frame in range(FRAMES):
		await physics_frame
		var pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var omega: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var linear_velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		if not pose.is_finite() or not omega.is_finite() or not linear_velocity.is_finite() or omega.length_squared() > 1000000.0:
			finite = false
			break

		var local_omega: Vector3 = pose.basis.inverse() * omega
		var angular_momentum := Vector3(INERTIA.x * local_omega.x, INERTIA.y * local_omega.y, INERTIA.z * local_omega.z)
		max_momentum_error = maxf(max_momentum_error, absf(angular_momentum.length() - initial_momentum) / initial_momentum)
		angular_change = omega.distance_to(INITIAL_OMEGA)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	return {
		"enabled": enabled, "frames": FRAMES, "finite": finite,
		"angular_change": angular_change, "max_momentum_error": max_momentum_error
	}
