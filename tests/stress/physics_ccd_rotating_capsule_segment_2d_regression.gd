# Regression: a rotating capsule must sweep its full volume against
# finite static segments even with zero linear velocity.
# Run: godot --headless --path tests/stress --script res://physics_ccd_rotating_capsule_segment_2d_regression.gd
extends SceneTree

const FRAMES := 4
const INITIAL_ANGLE_PER_TICK := PI
const CAPSULE_RADIUS := 0.25
const CAPSULE_HEIGHT := 6.0
const TARGET_X := 2.3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = 0
	for offset in [Vector2.ZERO, Vector2(2048.0, -4096.0)]:
		for enabled in [false, true]:
			var result: Dictionary = await _case(enabled, offset)
			print("ROTATING_CAPSULE_SEGMENT_TOI:" + JSON.stringify(result))
			var initial_speed: float = float(result["initial_speed"])
			var minimum_speed: float = float(result["minimum_speed"])
			var passed: bool = bool(result["finite"])
			if enabled:
				passed = passed and minimum_speed < initial_speed * 0.98
			else:
				passed = passed and minimum_speed > initial_speed * 0.95
			if not passed:
				failed += 1

	if failed:
		printerr("2D rotating capsule-segment CCD regression failed: %d" % failed)
		quit(1)
	else:
		print("2D rotating capsule-segment CCD regression passed.")
		quit(0)


func _case(enabled: bool, offset: Vector2) -> Dictionary:
	var settings_key := "physics/2d/solver/ccd_rotational_bounds"
	var angular_limit_key := "physics/2d/solver/ccd_max_angular_motion"
	var max_omega_key := "physics/2d/solver/max_angular_velocity"
	var previous_enabled: Variant = ProjectSettings.get_setting(settings_key, false)
	var previous_limit: Variant = ProjectSettings.get_setting(angular_limit_key, 0.0)
	var previous_omega: Variant = ProjectSettings.get_setting(max_omega_key, 0.0)
	ProjectSettings.set_setting(settings_key, enabled)
	ProjectSettings.set_setting(angular_limit_key, 0.0)
	ProjectSettings.set_setting(max_omega_key, 0.0)
	var space: RID = PhysicsServer2D.space_create()
	ProjectSettings.set_setting(settings_key, previous_enabled)
	ProjectSettings.set_setting(angular_limit_key, previous_limit)
	ProjectSettings.set_setting(max_omega_key, previous_omega)

	var capsule: RID = PhysicsServer2D.capsule_shape_create()
	var segment: RID = PhysicsServer2D.segment_shape_create()
	PhysicsServer2D.shape_set_data(capsule, Vector2(CAPSULE_RADIUS, CAPSULE_HEIGHT))
	PhysicsServer2D.shape_set_data(segment, Rect2(Vector2(0.0, -0.3), Vector2(0.0, 0.3)))

	var initial_speed: float = INITIAL_ANGLE_PER_TICK * float(Engine.physics_ticks_per_second)
	var rotor: RID = PhysicsServer2D.body_create()
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

	var obstacle: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(obstacle, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(obstacle, segment)
	PhysicsServer2D.body_set_state(obstacle, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, offset + Vector2(TARGET_X, 0.0)))
	PhysicsServer2D.body_set_space(obstacle, space)
	PhysicsServer2D.body_set_space(rotor, space)
	PhysicsServer2D.space_set_active(space, true)

	var minimum_speed: float = INF
	var finite: bool = true
	for frame in range(FRAMES):
		await physics_frame
		var pose: Transform2D = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_TRANSFORM)
		var omega: float = PhysicsServer2D.body_get_state(rotor, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
		finite = pose.origin.is_finite() and not is_nan(omega) and not is_inf(omega)
		minimum_speed = minf(minimum_speed, absf(omega))
		if not finite:
			break

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(rotor)
	PhysicsServer2D.free_rid(obstacle)
	PhysicsServer2D.free_rid(capsule)
	PhysicsServer2D.free_rid(segment)
	PhysicsServer2D.free_rid(space)

	return {
		"enabled": enabled, "offset": offset, "initial_speed": initial_speed,
		"minimum_speed": minimum_speed, "finite": finite
	}
