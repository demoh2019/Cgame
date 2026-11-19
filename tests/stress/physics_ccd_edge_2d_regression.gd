# Regression: ray-based CCD must cast both leading rectangle vertices.
# Run: godot --headless --path tests/stress --script res://physics_ccd_edge_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer2D.space_create()
	var moving_shape := PhysicsServer2D.rectangle_shape_create()
	var target_shape := PhysicsServer2D.circle_shape_create()
	# Godot rectangles use half extents; support[0] is the upper corner.
	PhysicsServer2D.shape_set_data(moving_shape, Vector2(0.35, 1.5))
	PhysicsServer2D.shape_set_data(target_shape, 0.3)

	var target := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(target, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(target, target_shape)
	PhysicsServer2D.body_set_state(target, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(0.0, -1.5)))
	PhysicsServer2D.body_set_space(target, space)

	var moving := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(moving, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(moving, moving_shape)
	PhysicsServer2D.body_set_param(moving, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_continuous_collision_detection_mode(
			moving, PhysicsServer2D.CCD_MODE_CAST_RAY)
	PhysicsServer2D.body_set_state(moving, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(moving, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(-3.0, 0.0)))
	PhysicsServer2D.body_set_state(moving, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
			Vector2(420.0, 0.0))
	PhysicsServer2D.body_set_space(moving, space)
	PhysicsServer2D.space_set_active(space, true)

	# The upper support ray misses. The lower support ray must stop the body.
	await physics_frame
	await physics_frame
	var result: Transform2D = PhysicsServer2D.body_get_state(
			moving, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var passed := result.origin.is_finite() and result.origin.x < -0.2
	if not passed:
		printerr("FAIL: the lower support ray missed the target; x = %f" % result.origin.x)

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(moving)
	PhysicsServer2D.free_rid(target)
	PhysicsServer2D.free_rid(moving_shape)
	PhysicsServer2D.free_rid(target_shape)
	PhysicsServer2D.free_rid(space)
	print("2D CCD edge regression: %s" % ("passed" if passed else "FAILED"))
	quit(0 if passed else 1)
