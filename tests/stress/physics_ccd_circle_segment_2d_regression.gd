# Regression for analytic circle-versus-segment CCD in GodotPhysics2D.
# Run: godot --headless --path tests/stress --script res://physics_ccd_circle_segment_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_body(space: RID, shape: RID, origin: Vector2, moving: bool) -> RID:
	var body: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID if moving else PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, origin))
	if moving:
		PhysicsServer2D.body_set_continuous_collision_detection_mode(body, PhysicsServer2D.CCD_MODE_CAST_RAY)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(480.0, 0.0))
	PhysicsServer2D.body_set_space(body, space)
	return body


func _run_case(label: String, moving_segment: bool, target_y: float, expected_braking: bool) -> int:
	var space: RID = PhysicsServer2D.space_create()
	var circle: RID = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)
	var segment: RID = PhysicsServer2D.segment_shape_create()
	# Segment shape data stores the two endpoints, not a box size.
	PhysicsServer2D.shape_set_data(segment, Rect2(Vector2(0.0, -1.0), Vector2(0.0, 1.0)))

	var moving_shape: RID = segment if moving_segment else circle
	var static_shape: RID = circle if moving_segment else segment
	var a: RID = _make_body(space, moving_shape, Vector2.ZERO, true)
	var b: RID = _make_body(space, static_shape, Vector2(4.0, target_y), false)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var velocity: Vector2 = PhysicsServer2D.body_get_state(a, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var transform_a: Transform2D = PhysicsServer2D.body_get_state(a, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var transform_b: Transform2D = PhysicsServer2D.body_get_state(b, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var valid: bool = velocity.is_finite() and transform_a.origin.is_finite() and transform_b.origin.is_finite()
	if expected_braking:
		valid = valid and velocity.x >= 0.0 and velocity.x < 350.0
	else:
		valid = valid and velocity.x > 400.0 and velocity.x < 500.0
	if not valid:
		printerr("FAIL %s: A velocity=%s, A=%s, B=%s" % [label, velocity, transform_a.origin, transform_b.origin])
	else:
		print("PASS %s: A velocity=%.3f" % [label, velocity.x])

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(a)
	PhysicsServer2D.free_rid(b)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(segment)
	PhysicsServer2D.free_rid(space)
	return 0 if valid else 1


func _run() -> void:
	var failures: int = 0
	# An endpoint is 0.4 above/below the circle's center path: the
	# point ray misses the segment, but the circle of radius 0.5 hits.
	failures += await _run_case("glancing circle against segment", false, 1.4, true)
	# Reverse the order: the entire segment moves into a static circle.
	failures += await _run_case("moving segment against circle", true, 1.4, true)
	# At offset 0.55 the moving radius-0.5 circle cannot touch the end.
	failures += await _run_case("segment endpoint beyond circle reach", false, 1.55, false)
	if failures:
		printerr("2D circle-segment CCD regression failed: %d" % failures)
		quit(1)
	else:
		print("2D circle-segment CCD regression passed.")
		quit(0)
