# Compare the old normalized-Euler gyroscope against optional implicit midpoint.
# Run: godot --headless --path tests/stress --script res://physics_gyroscopic_midpoint_3d_regression.gd
extends SceneTree

const FRAMES := 360
const OMEGA := Vector3(3.0, 5.0, 7.0)
const INERTIA := Vector3(1.0, 2.0, 4.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var euler: Dictionary = await _exercise(0)
	var midpoint: Dictionary = await _exercise(1)
	print("GYRO_NORMALIZED_EULER:" + JSON.stringify(euler))
	print("GYRO_IMPLICIT_MIDPOINT:" + JSON.stringify(midpoint))
	var valid := bool(euler.get("finite", false)) and bool(midpoint.get("finite", false))
	valid = valid and float(midpoint.get("peak_energy_error", 1.0)) < 0.02
	valid = valid and float(midpoint.get("peak_momentum_error", 1.0)) < 0.02
	valid = valid and float(midpoint.get("omega_change", 0.0)) > 0.05
	if valid:
		print("Midpoint gyroscope torque-free energy regression passed.")
		quit(0)
	else:
		printerr("Midpoint gyroscope torque-free energy regression failed.")
		quit(1)


func _exercise(mode: int) -> Dictionary:
	const ENABLE := "physics/3d/solver/gyroscopic_forces"
	const MODE := "physics/3d/solver/gyroscopic_integration_mode"
	var old_enable: Variant = ProjectSettings.get_setting(ENABLE, false)
	var old_mode: Variant = ProjectSettings.get_setting(MODE, 0)
	ProjectSettings.set_setting(ENABLE, true)
	ProjectSettings.set_setting(MODE, mode)
	var space: RID = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(ENABLE, old_enable)
	ProjectSettings.set_setting(MODE, old_mode)

	var shape: RID = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(1.0, 2.0, 3.0))
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_INERTIA, INERTIA)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(0.0, 10.0, 0.0)))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, OMEGA)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.space_set_active(space, true)

	var momentum_0 := Vector3(INERTIA.x * OMEGA.x, INERTIA.y * OMEGA.y,
			INERTIA.z * OMEGA.z).length()
	var energy_0 := 0.5 * (INERTIA.x * OMEGA.x * OMEGA.x +
			INERTIA.y * OMEGA.y * OMEGA.y + INERTIA.z * OMEGA.z * OMEGA.z)
	var peak_energy_error := 0.0
	var peak_momentum_error := 0.0
	var omega_change := 0.0
	var finite := true
	for frame in range(FRAMES):
		await physics_frame
		var pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var world_omega: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if not pose.is_finite() or not world_omega.is_finite() or world_omega.length_squared() > 1000000.0:
			finite = false
			break

		var principal_omega: Vector3 = pose.basis.inverse() * world_omega
		var angular_momentum := Vector3(INERTIA.x * principal_omega.x,
				INERTIA.y * principal_omega.y, INERTIA.z * principal_omega.z)
		var energy := 0.5 * (INERTIA.x * principal_omega.x * principal_omega.x +
				INERTIA.y * principal_omega.y * principal_omega.y +
				INERTIA.z * principal_omega.z * principal_omega.z)
		peak_energy_error = maxf(peak_energy_error, absf(energy - energy_0) / energy_0)
		peak_momentum_error = maxf(peak_momentum_error, absf(angular_momentum.length() - momentum_0) / momentum_0)
		omega_change = world_omega.distance_to(OMEGA)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	return {
		"mode": mode, "finite": finite, "frames": FRAMES,
		"peak_energy_error": peak_energy_error,
		"peak_momentum_error": peak_momentum_error,
		"omega_change": omega_change,
	}
