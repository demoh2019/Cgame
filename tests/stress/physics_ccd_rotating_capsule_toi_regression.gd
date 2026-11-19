# Nonlinear pure-rotation CCD: a capsule sweeps through a stationary
# circle/sphere and finishes the step back outside the target.
# Run with a built-in GodotPhysics Cgame binary:
# godot --headless --path tests/stress --script res://physics_ccd_rotating_capsule_toi_regression.gd
extends SceneTree

const FRAMES := 4
const INITIAL_ANGLE_PER_TICK := PI
const RADIUS := 0.25
const HEIGHT := 6.0
const TARGET_RADIUS := 0.3
const TARGET_X := 2.3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results: Array[Dictionary] = []
	for dim in [2, 3]:
		# The same rotation must work outside world origin. A translated
		# rotor also exercises an explicitly offset center of mass.
		for offset in [Vector2.ZERO, Vector2(2048.0, -4096.0)]:
			results.append(await _case(dim, false, offset))
			results.append(await _case(dim, true, offset))
	var valid := true
	for result in results:
		print("ROTATING_CAPSULE_TOI:" + JSON.stringify(result))
		valid = valid and bool(result.get("finite", false))
		var initial_speed := float(result["initial_speed"])
		if bool(result["enabled"]):
			valid = valid and float(result["minimum_speed"]) < initial_speed * 0.98
		else:
			valid = valid and float(result["minimum_speed"]) > initial_speed * 0.95
	if valid:
		print("2D/3D nonlinear rotation-only capsule CCD regression passed.")
		quit(0)
	else:
		printerr("FAIL: nonlinear rotating-capsule CCD regression")
		quit(1)


func _case(dim: int, enabled: bool, offset: Vector2 = Vector2.ZERO) -> Dictionary:
	var bounds_key := "physics/%dd/solver/ccd_rotational_bounds" % dim
	var limit_key := "physics/%dd/solver/ccd_max_angular_motion" % dim
	var max_speed_key := "physics/%dd/solver/max_angular_velocity" % dim
	var saved_bounds: Variant = ProjectSettings.get_setting(bounds_key, false)
	var saved_limit: Variant = ProjectSettings.get_setting(limit_key, 0.0)
	var saved_speed: Variant = ProjectSettings.get_setting(max_speed_key, 0.0)
	ProjectSettings.set_setting(bounds_key, enabled)
	ProjectSettings.set_setting(limit_key, 0.0)
	ProjectSettings.set_setting(max_speed_key, 0.0)
	var space: RID = PhysicsServer2D.space_create() if dim == 2 else PhysicsServer3D.space_create()
	ProjectSettings.set_setting(bounds_key, saved_bounds)
	ProjectSettings.set_setting(limit_key, saved_limit)
	ProjectSettings.set_setting(max_speed_key, saved_speed)

	var capsule: RID
	var sphere: RID
	var rotor: RID
	var stationary: RID
	var initial_speed := INITIAL_ANGLE_PER_TICK * float(Engine.physics_ticks_per_second)
	if dim == 2:
		capsule = PhysicsServer2D.capsule_shape_create()
		sphere = PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(capsule, Vector2(RADIUS, HEIGHT))
		PhysicsServer2D.shape_set_data(sphere, TARGET_RADIUS)
		rotor = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(rotor, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(rotor, capsule)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, offset))
		if offset != Vector2.ZERO:
			PhysicsServer2D.body_set_param(rotor, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS, Vector2(0.2, 0.0))
		PhysicsServer2D.body_set_state(rotor, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, initial_speed)
		PhysicsServer2D.body_set_continuous_collision_detection_mode(rotor, PhysicsServer2D.CCD_MODE_CAST_RAY)
		stationary = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(stationary, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(stationary, sphere)
		PhysicsServer2D.body_set_state(stationary, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, offset + Vector2(TARGET_X, 0)))
		PhysicsServer2D.body_set_space(stationary, space)
		PhysicsServer2D.body_set_space(rotor, space)
		PhysicsServer2D.space_set_active(space, true)
	else:
		capsule = PhysicsServer3D.capsule_shape_create()
		sphere = PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(capsule, {"radius": RADIUS, "height": HEIGHT})
		PhysicsServer3D.shape_set_data(sphere, TARGET_RADIUS)
		rotor = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rotor, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(rotor, capsule)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(offset.x, offset.y, 0.0)))
		if offset != Vector2.ZERO:
			PhysicsServer3D.body_set_param(rotor, PhysicsServer3D.BODY_PARAM_CENTER_OF_MASS, Vector3(0.2, 0.0, 0.0))
		PhysicsServer3D.body_set_state(rotor, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
				Vector3(0, 0, initial_speed))
		PhysicsServer3D.body_set_enable_continuous_collision_detection(rotor, true)
		stationary = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(stationary, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(stationary, sphere)
		PhysicsServer3D.body_set_state(stationary, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(offset.x + TARGET_X, offset.y, 0)))
		PhysicsServer3D.body_set_space(stationary, space)
		PhysicsServer3D.body_set_space(rotor, space)
		PhysicsServer3D.space_set_active(space, true)

	var minimum_speed := INF
	var finite := true
	for frame in range(FRAMES):
		await physics_frame
		if dim == 2:
			var pose: Transform2D = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var omega: float = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
			finite = pose.origin.is_finite() and not is_nan(omega) and not is_inf(omega)
			minimum_speed = minf(minimum_speed, absf(omega))
		else:
			var pose: Transform3D = PhysicsServer3D.body_get_state(rotor, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var omega: Vector3 = PhysicsServer3D.body_get_state(rotor, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			finite = pose.is_finite() and omega.is_finite()
			minimum_speed = minf(minimum_speed, omega.length())
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

	return {
		"dimension": dim, "enabled": enabled, "offset": offset, "frames": FRAMES,
		"initial_speed": initial_speed, "minimum_speed": minimum_speed,
		"finite": finite
	}
