# Compare material restitution mixing in two isolated physics spaces per
# dimension. Run with GodotPhysics backends enabled:
# godot --headless --path tests/stress --script res://physics_restitution_mix_regression.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var result_2d: Dictionary = await _compare_2d()
	var result_3d: Dictionary = await _compare_3d()
	var passed: bool = bool(result_2d["passed"]) and bool(result_3d["passed"])
	print("RESTITUTION_MIX_RESULT:" + JSON.stringify({"passed": passed, "2d": result_2d, "3d": result_3d}))
	quit(0 if passed else 1)

func _compare_2d() -> Dictionary:
	const KEY = "physics/2d/solver/restitution_combine_mode"
	var old_setting: Variant = ProjectSettings.get_setting(KEY, 0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []
	var movers: Array[RID] = []
	for mode in [0, 4]:
		ProjectSettings.set_setting(KEY, mode)
		var space := PhysicsServer2D.space_create()
		ProjectSettings.set_setting(KEY, old_setting)
		spaces.append(space)
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0.0)
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_LINEAR_DAMP, 0.0)
		var floor_shape := PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(floor_shape, Vector2(120.0, 5.0))
		var ball_shape := PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(ball_shape, 5.0)
		shapes.append(floor_shape)
		shapes.append(ball_shape)
		var floor := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(floor, floor_shape)
		PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_BOUNCE, 0.25)
		PhysicsServer2D.body_set_space(floor, space)
		bodies.append(floor)
		var ball := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(ball, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(ball, ball_shape)
		PhysicsServer2D.body_set_param(ball, PhysicsServer2D.BODY_PARAM_BOUNCE, 0.50)
		PhysicsServer2D.body_set_param(ball, PhysicsServer2D.BODY_PARAM_FRICTION, 0.0)
		PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.0, -30.0)))
		PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(0.0, 350.0))
		PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_space(ball, space)
		bodies.append(ball)
		movers.append(ball)
		PhysicsServer2D.space_set_active(space, true)
	var peak: Array[float] = [0.0, 0.0]
	for frame in range(70):
		await physics_frame
		for i in range(2):
			var velocity: Vector2 = PhysicsServer2D.body_get_state(movers[i], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			peak[i] = maxf(peak[i], -velocity.y)
	for space in spaces:
		PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for shape in shapes:
		PhysicsServer2D.free_rid(shape)
	for space in spaces:
		PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(KEY, old_setting)
	return {"passed": peak[0] > peak[1] + 50.0 and peak[1] > 1.0, "legacy": peak[0], "multiply": peak[1]}

func _compare_3d() -> Dictionary:
	const KEY = "physics/3d/solver/restitution_combine_mode"
	var old_setting: Variant = ProjectSettings.get_setting(KEY, 0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []
	var movers: Array[RID] = []
	for mode in [0, 4]:
		ProjectSettings.set_setting(KEY, mode)
		var space := PhysicsServer3D.space_create()
		ProjectSettings.set_setting(KEY, old_setting)
		spaces.append(space)
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_LINEAR_DAMP, 0.0)
		var floor_shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(floor_shape, Vector3(120.0, 1.0, 120.0))
		var ball_shape := PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(ball_shape, 1.0)
		shapes.append(floor_shape)
		shapes.append(ball_shape)
		var floor := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(floor, floor_shape)
		PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.25)
		PhysicsServer3D.body_set_space(floor, space)
		bodies.append(floor)
		var ball := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(ball, ball_shape)
		PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.50)
		PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_FRICTION, 0.0)
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0.0, 4.0, 0.0)))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(0.0, -20.0, 0.0))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_space(ball, space)
		bodies.append(ball)
		movers.append(ball)
		PhysicsServer3D.space_set_active(space, true)
	var peak: Array[float] = [0.0, 0.0]
	for frame in range(70):
		await physics_frame
		for i in range(2):
			var velocity: Vector3 = PhysicsServer3D.body_get_state(movers[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			peak[i] = maxf(peak[i], velocity.y)
	for space in spaces:
		PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	for space in spaces:
		PhysicsServer3D.free_rid(space)
	ProjectSettings.set_setting(KEY, old_setting)
	return {"passed": peak[0] > peak[1] + 4.0 and peak[1] > 0.2, "legacy": peak[0], "multiply": peak[1]}
