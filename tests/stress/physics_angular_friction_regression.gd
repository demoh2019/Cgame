# Test optional rolling (2D) and spinning (3D) resistance.
extends SceneTree

const FRAMES := 180

func _initialize() -> void:
	_execute.call_deferred()

func _execute() -> void:
	var two_off: Dictionary = await _two(false)
	var two_on: Dictionary = await _two(true)
	var three_off: Dictionary = await _three(false)
	var three_on: Dictionary = await _three(true)
	print("ANGULAR_FRICTION_2D:" + JSON.stringify([two_off, two_on]))
	print("ANGULAR_FRICTION_3D:" + JSON.stringify([three_off, three_on]))
	var valid := bool(two_off["finite"]) and bool(two_on["finite"]) and bool(three_off["finite"]) and bool(three_on["finite"])
	valid = valid and int(two_off["pairs"]) > 0 and int(two_on["pairs"]) > 0
	valid = valid and int(three_off["pairs"]) > 0 and int(three_on["pairs"]) > 0
	valid = valid and float(three_on["speed"]) < float(three_off["speed"])
	if valid:
		print("Angular contact friction regression passed.")
		quit(0)
	else:
		printerr("Angular contact friction regression failed.")
		quit(1)

func _two(enabled: bool) -> Dictionary:
	const SETTING := "physics/2d/solver/rolling_friction"
	var previous: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	ProjectSettings.set_setting(SETTING, 0.4 if enabled else 0.0)
	var space: RID = PhysicsServer2D.space_create()
	ProjectSettings.set_setting(SETTING, previous)
	var floor_shape: RID = PhysicsServer2D.rectangle_shape_create()
	var circle: RID = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(30, 0.5))
	PhysicsServer2D.shape_set_data(circle, 0.5)
	var floor: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(floor, floor_shape)
	PhysicsServer2D.body_set_space(floor, space)
	var ball: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(ball, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(ball, circle)
# Gravity points along +Y in PhysicsServer2D. The sphere must move
	# toward the floor to establish a normal impulse for angular friction.
		PhysicsServer2D.body_set_param(ball, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0, -1.45)))
	PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 12.0)
	PhysicsServer2D.body_set_space(ball, space)
	PhysicsServer2D.space_set_active(space, true)
	var finite := true
	var peak_pairs := 0
	var speed := 0.0
	for frame in range(FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		var pose: Transform2D = PhysicsServer2D.body_get_state(ball, PhysicsServer2D.BODY_STATE_TRANSFORM)
		var velocity: Vector2 = PhysicsServer2D.body_get_state(ball, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
		var omega: float = PhysicsServer2D.body_get_state(ball, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
		if not pose.origin.is_finite() or not velocity.is_finite() or is_nan(omega) or is_inf(omega):
			finite = false
			break
		speed = absf(omega)
	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(ball)
	PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)
	return {"enabled": enabled, "finite": finite, "pairs": peak_pairs, "speed": speed}

func _three(enabled: bool) -> Dictionary:
	const SETTING := "physics/3d/solver/spinning_friction"
	var previous: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	ProjectSettings.set_setting(SETTING, 0.4 if enabled else 0.0)
	var space: RID = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(SETTING, previous)
	var floor_shape: RID = PhysicsServer3D.box_shape_create()
	var sphere: RID = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(30, 1, 30))
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var floor: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_space(floor, space)
	var ball: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(ball, sphere)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 2.2, 0)))
	PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0, 12, 0))
	PhysicsServer3D.body_set_space(ball, space)
	PhysicsServer3D.space_set_active(space, true)
	var finite := true
	var peak_pairs := 0
	var speed := 0.0
	for frame in range(FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		var pose: Transform3D = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var velocity: Vector3 = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var omega: Vector3 = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if not pose.origin.is_finite() or not velocity.is_finite() or not omega.is_finite():
			finite = false
			break
		speed = absf(omega.y)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(ball)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)
	return {"enabled": enabled, "finite": finite, "pairs": peak_pairs, "speed": speed}
