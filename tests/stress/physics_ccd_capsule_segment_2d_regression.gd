# GodotPhysics2D volume-CCD regression for capsule versus finite segment.
# Run: godot --headless --path tests/stress --script res://physics_ccd_capsule_segment_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_body(space: RID, shape: RID, position: Vector2, moving: bool) -> RID:
	var body: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID if moving else PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, position))
	if moving:
		PhysicsServer2D.body_set_continuous_collision_detection_mode(body, PhysicsServer2D.CCD_MODE_CAST_RAY)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(480.0, 0.0))
	PhysicsServer2D.body_set_space(body, space)
	return body


func _run_case(label: String, moving_segment: bool, segment_y: float, expected_braking: bool) -> int:
	var space: RID = PhysicsServer2D.space_create()
	var capsule: RID = PhysicsServer2D.capsule_shape_create()
	# Radius 0.5 with centerline endpoints y = -1 and y = +1.
	PhysicsServer2D.shape_set_data(capsule, Vector2(0.5, 3.0))
	var segment: RID = PhysicsServer2D.segment_shape_create()
	# A finite, horizontal segment with endpoints (-1, 0) and (1, 0).
	PhysicsServer2D.shape_set_data(segment, Rect2(Vector2(-1.0, 0.0), Vector2(1.0, 0.0)))

	var moving_shape: RID = segment if moving_segment else capsule
	var static_shape: RID = capsule if moving_segment else segment
	var start: Vector2 = Vector2(0.0, segment_y) if moving_segment else Vector2.ZERO
	var target: Vector2 = Vector2(4.0, 0.0) if moving_segment else Vector2(4.0, segment_y)
	var a: RID = _make_body(space, moving_shape, start, true)
	var b: RID = _make_body(space, static_shape, target, false)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var velocity: Vector2 = PhysicsServer2D.body_get_state(a, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var transform_a: Transform2D = PhysicsServer2D.body_get_state(a, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var transform_b: Transform2D = PhysicsServer2D.body_get_state(b, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var passed: bool = velocity.is_finite() and transform_a.origin.is_finite() and transform_b.origin.is_finite()
	if expected_braking:
		passed = passed and velocity.x >= 0.0 and velocity.x < 350.0
	else:
		passed = passed and velocity.x > 400.0 and velocity.x < 500.0

	if not passed:
		printerr("FAIL %s: velocity=%s, moving=%s, target=%s" % [label, velocity, transform_a.origin, transform_b.origin])
	else:
		print("PASS %s: moving velocity=%.3f" % [label, velocity.x])

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(a)
	PhysicsServer2D.free_rid(b)
	PhysicsServer2D.free_rid(capsule)
	PhysicsServer2D.free_rid(segment)
	PhysicsServer2D.free_rid(space)
	return 0 if passed else 1


func _run() -> void:
	var failures: int = 0
	# A capsule end-cap grazes the near endpoint of a horizontal
	# segment. Its leading support ray at y=1 misses y=1.3.
	failures += await _run_case("moving capsule grazes segment endpoint", false, 1.3, true)
	# Reverse shape order while retaining the same relative motion.
	failures += await _run_case("moving segment grazes static capsule", true, 1.3, true)
	# At y=1.6, the segment stays beyond the full radius of the cap.
	failures += await _run_case("capsule segment separated", false, 1.6, false)
	if failures:
		printerr("2D capsule-segment CCD regression failed: %d" % failures)
		quit(1)
	else:
		print("2D capsule-segment CCD regression passed.")
		quit(0)
