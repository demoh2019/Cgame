# Per-step CCD angular displacement limit smoke test for GodotPhysics2D/3D.
# Run: godot --headless --path tests/stress --script res://physics_ccd_angular_motion_regression.gd
extends SceneTree

const MAX_ROTATION := PI / 4.0
const INITIAL_SPEED := 120.0
const FRAMES := 12


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results: Array[Dictionary] = []
	for dimension in [2, 3]:
		results.append(await _exercise(dimension, false))
		results.append(await _exercise(dimension, true))
	var invalid := false
	for result in results:
		print("CCD_ANGULAR_MOTION:" + JSON.stringify(result))
		if not bool(result["valid"]):
			invalid = true
	if invalid:
		printerr("CCD angular motion regression failed.")
		quit(1)
	else:
		print("2D/3D CCD-only angular motion limit regression passed.")
		quit(0)


func _exercise(dimension: int, ccd: bool) -> Dictionary:
	var setting := "physics/%dd/solver/ccd_max_angular_motion" % dimension
	var global_setting := "physics/%dd/solver/max_angular_velocity" % dimension
	var old_setting: Variant = ProjectSettings.get_setting(setting, 0.0)
	var old_global: Variant = ProjectSettings.get_setting(global_setting, 0.0)
	ProjectSettings.set_setting(setting, MAX_ROTATION)
	ProjectSettings.set_setting(global_setting, 0.0)
	var space: RID
	var body: RID
	var shape: RID
	if dimension == 2:
		space = PhysicsServer2D.space_create()
	else:
		space = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(setting, old_setting)
	ProjectSettings.set_setting(global_setting, old_global)

	if dimension == 2:
		shape = PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(shape, Vector2(3.0, 0.1))
		body = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE,
				PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, INITIAL_SPEED)
		if ccd:
			PhysicsServer2D.body_set_continuous_collision_detection_mode(body, PhysicsServer2D.CCD_MODE_CAST_SHAPE)
		PhysicsServer2D.body_set_space(body, space)
		PhysicsServer2D.space_set_active(space, true)
	else:
		shape = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, Vector3(6.0, 0.2, 0.2))
		body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,
				PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
				Vector3(0.0, INITIAL_SPEED, 0.0))
		PhysicsServer3D.body_set_enable_continuous_collision_detection(body, ccd)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.space_set_active(space, true)

	var measured_peak := 0.0
	var measured_low := INF
	var finite := true
	for frame in range(FRAMES):
		await physics_frame
		var measured := 0.0
		if dimension == 2:
			var pose: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var omega: float = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
			finite = pose.origin.is_finite() and not is_nan(omega) and not is_inf(omega)
			measured = absf(omega)
		else:
			var pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var omega: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			finite = pose.is_finite() and omega.is_finite()
			measured = omega.length()
		if not finite:
			break
		measured_peak = maxf(measured_peak, measured)
		measured_low = minf(measured_low, measured)

	if dimension == 2:
		PhysicsServer2D.space_set_active(space, false)
		PhysicsServer2D.free_rid(body)
		PhysicsServer2D.free_rid(shape)
		PhysicsServer2D.free_rid(space)
	else:
		PhysicsServer3D.space_set_active(space, false)
		PhysicsServer3D.free_rid(body)
		PhysicsServer3D.free_rid(shape)
		PhysicsServer3D.free_rid(space)

	var speed_cap := MAX_ROTATION * float(Engine.physics_ticks_per_second)
	var valid := finite and measured_low > 0.0
	if ccd:
		valid = valid and measured_peak <= speed_cap + 0.01
	else:
		# No CCD => per-step cap must never affect the rigid body.
		valid = valid and measured_low >= INITIAL_SPEED - 0.1
	return {
		"dimension": dimension, "ccd_enabled": ccd, "finite": finite,
		"peak_speed": measured_peak, "minimum_speed": measured_low,
		"expected_ccd_speed_limit": speed_cap, "valid": valid
	}
