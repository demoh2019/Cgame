# Regression for native GodotPhysics3D CCD against moving targets.
# Run with GodotPhysics3D explicitly selected in project settings:
# godot --headless --path tests/stress --script res://physics_ccd_relative_motion_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_body(space: RID, shape: RID, x: float, velocity: float, ccd: bool, static_body: bool = false, y: float = 0.0) -> RID:
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC if static_body else PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(x, y, 0.0)))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
			Vector3(velocity, 0.0, 0.0))
	if ccd:
		PhysicsServer3D.body_set_enable_continuous_collision_detection(body, true)
	PhysicsServer3D.body_set_space(body, space)
	return body


func _run_case(label: String, target_x: float, velocity_a: float, velocity_b: float,
		min_speed: float, max_speed: float, static_target: bool = false, target_ccd: bool = false, target_y: float = 0.0, capsule_target: bool = false, source_y: float = 0.0, capsule_source: bool = false, reversed_target_axis: bool = false) -> int:
	var space: RID = PhysicsServer3D.space_create()
	var sphere: RID = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)

	var source_shape: RID = sphere
	if capsule_source:
		source_shape = PhysicsServer3D.capsule_shape_create()
		PhysicsServer3D.shape_set_data(source_shape, {"radius": 0.5, "height": 4.0})
	var a: RID = _make_body(space, source_shape, 0.0, velocity_a, true, false, source_y)
	var target_shape: RID = sphere
	if capsule_target:
		target_shape = PhysicsServer3D.capsule_shape_create()
		PhysicsServer3D.shape_set_data(target_shape, {"radius": 0.5, "height": 4.0})
	var b: RID = _make_body(space, target_shape, target_x, velocity_b, target_ccd, static_target, target_y)
	if reversed_target_axis:
		PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(Vector3(0.0, 0.0, 1.0), PI), Vector3(target_x, target_y, 0.0)))
	PhysicsServer3D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var after_a: Vector3 = PhysicsServer3D.body_get_state(a, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var after_b: Vector3 = PhysicsServer3D.body_get_state(b, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var transform_a: Transform3D = PhysicsServer3D.body_get_state(a, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var transform_b: Transform3D = PhysicsServer3D.body_get_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var passed: bool = after_a.is_finite() and after_b.is_finite()
	passed = passed and transform_a.origin.is_finite() and transform_b.origin.is_finite()
	passed = passed and after_a.x >= min_speed and after_a.x <= max_speed
	if static_target:
		passed = passed and absf(transform_b.origin.x - target_x) < 0.01

	if not passed:
		printerr("FAIL %s: A velocity=%s, B velocity=%s; A=%s, B=%s; expected A speed=[%s, %s]" %
				[label, after_a, after_b, transform_a.origin, transform_b.origin, min_speed, max_speed])
	else:
		print("PASS %s: A velocity=%.3f, B velocity=%.3f" % [label, after_a.x, after_b.x])

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(a)
	PhysicsServer3D.free_rid(b)
	PhysicsServer3D.free_rid(sphere)
	if capsule_target:
		PhysicsServer3D.free_rid(target_shape)
	if capsule_source:
		PhysicsServer3D.free_rid(source_shape)
	PhysicsServer3D.free_rid(space)
	return 0 if passed else 1


func _run() -> void:
	var failures: int = 0
	# Enable swept proxies on both bodies for tests that start with B
	# behind A: otherwise the pair may never reach the CCD narrowphase.
	failures += await _run_case("co-moving bodies", -1.02, 600.0, 600.0, 525.0, 625.0, false, true)
	failures += await _run_case("slower trailing body", -1.02, 600.0, 300.0, 525.0, 625.0, false, true)

	# A closes on a slower B ahead; only A's velocity should be reduced.
	failures += await _run_case("slower body ahead", 1.02, 600.0, 300.0, 0.0, 525.0)

	# A static body's surface velocity contributes to friction but must
	# not move its collision shape during CCD.
	failures += await _run_case("static conveyor surface", 1.02, 600.0, 600.0, 0.0, 525.0, true)

	# The leading support ray runs along y=0 and misses a radius-0.5
	# obstacle at y=0.8. A swept radius-one Minkowski sphere does hit it.
	# Analytic circle/sphere TOI must catch this glancing collision.
	failures += await _run_case("glancing sphere CCD", 4.0, 480.0, 0.0, 0.0, 440.0, true, false, 0.8)
	# A point ray at y=0 misses the capsule's lower cap (center y=0.7,
	# radius 0.5), but the swept radius-0.5 sphere intersects it.
	failures += await _run_case("glancing capsule CCD", 4.0, 480.0, 0.0, 0.0, 470.0, true, false, 2.2, true)
	# Reversed order: A is a capsule centered at y=2.2 and sweeps
	# into the static circle/sphere B at x=4, y=0.
	failures += await _run_case("moving capsule CCD", 4.0, 480.0, 0.0, 0.0, 470.0, true, false, 0.0, false, 2.2, true)
	# Parallel capsule center segments combine into a longer expanded
	# capsule. Their first grazing contact must be found by volume TOI.
	failures += await _run_case("parallel capsules CCD", 4.0, 480.0, 0.0, 0.0, 425.0, true, false, 3.8, true, 0.0, true)
	# Reversing a capsule axis gives the same center segment Minkowski sum.
	failures += await _run_case("antiparallel capsules CCD", 4.0, 480.0, 0.0, 0.0, 425.0, true, false, 3.8, true, 0.0, true, true)

	if failures:
		printerr("3D relative-motion CCD regression failed: %d" % failures)
		quit(1)
	else:
		print("3D relative-motion CCD regression passed.")
		quit(0)
