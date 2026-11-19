# Regression: a capsule translates and rotates through a stationary
# circle/sphere during a single physics step, without overlapping at either
# endpoint. The nonlinear TOI is opt-in via ccd_rotational_bounds.
# Run: godot --headless --path tests/stress --script res://physics_ccd_nonlinear_capsule_toi_regression.gd
extends SceneTree

const FRAMES := 4
const ANGLE_PER_TICK := PI
const LINEAR_TRAVEL_PER_TICK := 0.1
const CAPSULE_RADIUS := 0.25
const CAPSULE_HEIGHT := 6.0
const TARGET_RADIUS := 0.3
const TARGET_X := 2.3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: int = 0
	for dim in [2, 3]:
		for offset in [Vector2.ZERO, Vector2(2048.0, -4096.0)]:
			for enabled in [false, true]:
				var result: Dictionary = await _case(dim, enabled, offset)
				print("MIXED_CAPSULE_TOI:" + JSON.stringify(result))
				var initial_omega: float = float(result["initial_omega"])
				var initial_linear: float = float(result["initial_linear"])
				var passed: bool = bool(result["finite"])
				if enabled:
					passed = passed and float(result["minimum_omega"]) < initial_omega * 0.98
					passed = passed and float(result["minimum_linear"]) < initial_linear * 0.98
				else:
					passed = passed and float(result["minimum_omega"]) > initial_omega * 0.95
					passed = passed and float(result["minimum_linear"]) > initial_linear * 0.95
				if not passed:
					failures += 1

	if failures:
		printerr("2D/3D mixed nonlinear capsule CCD regression failed: %d" % failures)
		quit(1)
	else:
		print("2D/3D mixed nonlinear capsule CCD regression passed.")
		quit(0)


func _case(dim: int, enabled: bool, offset: Vector2) -> Dictionary:
	var bounds_key: String = "physics/%dd/solver/ccd_rotational_bounds" % dim
	var limit_key: String = "physics/%dd/solver/ccd_max_angular_motion" % dim
	var max_omega_key: String = "physics/%dd/solver/max_angular_velocity" % dim
	var old_bounds: Variant = ProjectSettings.get_setting(bounds_key, false)
	var old_limit: Variant = ProjectSettings.get_setting(limit_key, 0.0)
	var old_max_omega: Variant = ProjectSettings.get_setting(max_omega_key, 0.0)
	ProjectSettings.set_setting(bounds_key, enabled)
	ProjectSettings.set_setting(limit_key, 0.0)
	ProjectSettings.set_setting(max_omega_key, 0.0)
	var space: RID = PhysicsServer2D.space_create() if dim == 2 else PhysicsServer3D.space_create()
	ProjectSettings.set_setting(bounds_key, old_bounds)
	ProjectSettings.set_setting(limit_key, old_limit)
	ProjectSettings.set_setting(max_omega_key, old_max_omega)

	var initial_omega: float = ANGLE_PER_TICK * float(Engine.physics_ticks_per_second)
	var initial_linear: float = LINEAR_TRAVEL_PER_TICK * float(Engine.physics_ticks_per_second)
	var capsule: RID
	var sphere: RID
	var rotor: RID
	var stationary: RID
	if dim == 2:
		capsule = PhysicsServer2D.capsule_shape_create()
		sphere = PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(capsule, Vector2(CAPSULE_RADIUS, CAPSULE_HEIGHT))
		PhysicsServer2D.shape_set_data(sphere, TARGET_RADIUS)
		rotor = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(rotor, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(rotor, capsule)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, offset))
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(initial_linear, 0.0))
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, initial_omega)
		PhysicsServer2D.body_set_continuous_collision_detection_mode(rotor, PhysicsServer2D.CCD_MODE_CAST_RAY)
		stationary = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(stationary, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(stationary, sphere)
		PhysicsServer2D.body_set_state(stationary, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, offset + Vector2(TARGET_X, 0.0)))
		PhysicsServer2D.body_set_space(stationary, space)
		PhysicsServer2D.body_set_space(rotor, space)
		PhysicsServer2D.space_set_active(space, true)
	else:
		capsule = PhysicsServer3D.capsule_shape_create()
		sphere = PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(capsule, {"radius": CAPSULE_RADIUS, "height": CAPSULE_HEIGHT})
		PhysicsServer3D.shape_set_data(sphere, TARGET_RADIUS)
		rotor = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rotor, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(rotor, capsule)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(offset.x, offset.y, 0.0)))
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(initial_linear, 0.0, 0.0))
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 0.0, initial_omega))
		PhysicsServer3D.body_set_enable_continuous_collision_detection(rotor, true)
		stationary = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(stationary, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(stationary, sphere)
		PhysicsServer3D.body_set_state(stationary, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(offset.x + TARGET_X, offset.y, 0.0)))
		PhysicsServer3D.body_set_space(stationary, space)
		PhysicsServer3D.body_set_space(rotor, space)
		PhysicsServer3D.space_set_active(space, true)

	var minimum_omega: float = INF
	var minimum_linear: float = INF
	var finite: bool = true
	for frame in range(FRAMES):
		await physics_frame
		if dim == 2:
			var pose: Transform2D = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var omega: float = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
			var linear: Vector2 = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			finite = pose.origin.is_finite() and linear.is_finite() and not is_nan(omega) and not is_inf(omega)
			minimum_omega = minf(minimum_omega, absf(omega))
			minimum_linear = minf(minimum_linear, linear.length())
		else:
			var pose: Transform3D = PhysicsServer3D.body_get_state(rotor, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var omega: Vector3 = PhysicsServer3D.body_get_state(rotor, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			var linear: Vector3 = PhysicsServer3D.body_get_state(rotor, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			finite = pose.is_finite() and omega.is_finite() and linear.is_finite()
			minimum_omega = minf(minimum_omega, omega.length())
			minimum_linear = minf(minimum_linear, linear.length())
		if not finite:
			break

	if dim == 2:
		PhysicsServer2D.space_set_active(space, false)
		PhysicsServer2D.free_rid(rotor)
		PhysicsServer2D.free_rid(stationary)
		PhysicsServer2D.free_rid(capsule)
		PhysicsServer2D.free_rid(sphere)
		PhysicsServer2D.free_rid(space)
	else:
		PhysicsServer3D.space_set_active(space, false)
		PhysicsServer3D.free_rid(rotor)
		PhysicsServer3D.free_rid(stationary)
		PhysicsServer3D.free_rid(capsule)
		PhysicsServer3D.free_rid(sphere)
		PhysicsServer3D.free_rid(space)

	return {"dimension": dim, "enabled": enabled, "offset": offset,
			"initial_omega": initial_omega, "initial_linear": initial_linear,
			"minimum_omega": minimum_omega, "minimum_linear": minimum_linear,
			"finite": finite}
