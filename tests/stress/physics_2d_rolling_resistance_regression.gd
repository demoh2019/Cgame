extends SceneTree

# Compare coasting and rolling drag in two isolated GodotPhysics2D spaces.
# Run: godot --headless --path tests/stress --script res://physics_2d_rolling_resistance_regression.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	const SETTING = "physics/2d/solver/rolling_resistance"
	var original: Variant = ProjectSettings.get_setting(SETTING, 0.0)
	var spaces: Array[RID] = []
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []
	var rollers: Array[RID] = []

	for resistance in [0.0, 0.25]:
		ProjectSettings.set_setting(SETTING, resistance)
		var space := PhysicsServer2D.space_create()
		ProjectSettings.set_setting(SETTING, original)
		spaces.append(space)
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_ANGULAR_DAMP, 0.0)

		var floor_shape := PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(floor_shape, Vector2(3000.0, 4.0))
		var circle_shape := PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(circle_shape, 10.0)
		shapes.append(floor_shape)
		shapes.append(circle_shape)

		var floor := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(floor, floor_shape)
		PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, 1.0)
		PhysicsServer2D.body_set_space(floor, space)
		bodies.append(floor)

		var roller := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(roller, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(roller, circle_shape)
		PhysicsServer2D.body_set_param(roller, PhysicsServer2D.BODY_PARAM_FRICTION, 1.0)
		PhysicsServer2D.body_set_param(roller, PhysicsServer2D.BODY_PARAM_BOUNCE, 0.0)
		PhysicsServer2D.body_set_state(roller, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(roller, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(0.0, -12.0)))
		PhysicsServer2D.body_set_state(roller, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(80.0, 0.0))
		PhysicsServer2D.body_set_state(roller, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 8.0)
		PhysicsServer2D.body_set_space(roller, space)
		bodies.append(roller)
		rollers.append(roller)
		PhysicsServer2D.space_set_active(space, true)

	for frame in range(90):
		await physics_frame

	var baseline: float = absf(PhysicsServer2D.body_get_state(rollers[0], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY))
	var resisted: float = absf(PhysicsServer2D.body_get_state(rollers[1], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY))
	var passed: bool = baseline > 2.0 and resisted + 1.0 < baseline and resisted < 1000.0

	for space in spaces:
		PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	for shape in shapes:
		PhysicsServer2D.free_rid(shape)
	for space in spaces:
		PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(SETTING, original)

	print("ROLLING_RESISTANCE_2D_RESULT:" + JSON.stringify({
		"passed": passed, "baseline_angular_speed": baseline, "resisted_angular_speed": resisted
	}))
	quit(0 if passed else 1)
