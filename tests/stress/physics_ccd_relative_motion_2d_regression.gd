# Regression: cast-ray CCD must sweep in the moving target's relative frame.
# Run: godot --headless --path tests/stress --script res://physics_ccd_relative_motion_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_body(space: RID, shape: RID, x: float, velocity: float, ccd: bool, static_body: bool = false, y: float = 0.0) -> RID:
	var body: RID = PhysicsServer2D.body_create()
	if static_body:
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	else:
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(x, y)))
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
			Vector2(velocity, 0.0))
	if ccd:
		PhysicsServer2D.body_set_continuous_collision_detection_mode(body, PhysicsServer2D.CCD_MODE_CAST_RAY)
	PhysicsServer2D.body_set_space(body, space)
	return body


func _run_case(label: String, target_x: float, velocity_a: float, velocity_b: float,
		min_speed: float, max_speed: float, static_target: bool = false, target_ccd: bool = false, target_y: float = 0.0) -> int:
	var space: RID = PhysicsServer2D.space_create()
	var circle: RID = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)

	var a: RID = _make_body(space, circle, 0.0, velocity_a, true)
	var b: RID = _make_body(space, circle, target_x, velocity_b, target_ccd, static_target, target_y)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var after_a: Vector2 = PhysicsServer2D.body_get_state(a, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var after_b: Vector2 = PhysicsServer2D.body_get_state(b, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var transform_a: Transform2D = PhysicsServer2D.body_get_state(a, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var transform_b: Transform2D = PhysicsServer2D.body_get_state(b, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var passed: bool = after_a.is_finite() and after_b.is_finite()
	passed = passed and transform_a.origin.is_finite() and transform_b.origin.is_finite()
	passed = passed and after_a.x >= min_speed and after_a.x <= max_speed
	if static_target:
		passed = passed and absf(transform_b.origin.x - target_x) < 0.01

	if not passed:
		printerr("FAIL %s: A velocity=%s, B velocity=%s; A=%s B=%s; allowed A speed=[%s, %s]" %
				[label, after_a, after_b, transform_a.origin, transform_b.origin, min_speed, max_speed])
	else:
		print("PASS %s: A velocity=%.3f, B velocity=%.3f" % [label, after_a.x, after_b.x])

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(a)
	PhysicsServer2D.free_rid(b)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(space)
	return 0 if passed else 1


func _run() -> void:
	var failures: int = 0
	# These targets begin 0.02 units behind A's back surface. Both rays
	# overlap the *predicted* target position under the old algorithm, even
	# though A is not closing on B. Enable CCD on B too so its swept AABB
	# remains in the pair broadphase even though it begins behind A.
	# CCD must leave A's velocity alone.
	failures += await _run_case("co-moving bodies", -1.02, 600.0, 600.0, 525.0, 625.0, false, true)
	failures += await _run_case("slower trailing body", -1.02, 600.0, 300.0, 525.0, 625.0, false, true)

	# In contrast, a slower target directly ahead is approached by A.
	# An entering ray should shorten A's speed, without reversing it.
	failures += await _run_case("slower body ahead", 1.02, 600.0, 300.0, 0.0, 525.0)

	# Static bodies can expose constant surface velocity without moving
	# their collision geometry. The obstacle is stationary despite the
	# nonzero velocity used for contact friction, so A must still brake.
	failures += await _run_case("static conveyor surface", 1.02, 600.0, 600.0, 0.0, 525.0, true)

	# The leading support ray runs along y=0 and misses a radius-0.5
	# obstacle at y=0.8. A swept radius-one Minkowski sphere does hit it.
	# Analytic circle/sphere TOI must catch this glancing collision.
	failures += await _run_case("glancing sphere CCD", 4.0, 480.0, 0.0, 0.0, 440.0, true, false, 0.8)

	if failures:
		printerr("2D relative-motion CCD regression failed: %d" % failures)
		quit(1)
	else:
		print("2D relative-motion CCD regression passed.")
		quit(0)
