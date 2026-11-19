# Regression coverage for compound-body mass/centroid accumulation.
# Run: godot --headless --path tests/stress --script res://physics_compound_mass_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_body(space: RID, mass: float, offset: float) -> RID:
	var body: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_MASS, mass)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(offset, 0.0)))
	PhysicsServer2D.body_set_space(body, space)
	return body


func _check_mass(body: RID, name: String, expected_center: Vector2, expected_inertia: float) -> int:
	var center: Vector2 = PhysicsServer2D.body_get_param(body, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS)
	var inertia: float = PhysicsServer2D.body_get_param(body, PhysicsServer2D.BODY_PARAM_INERTIA)
	if not center.is_finite() or not is_finite(inertia):
		printerr("FAIL %s: non-finite center/inertia: %s / %s" % [name, center, inertia])
		return 1
	if center.distance_to(expected_center) > 0.001 or absf(inertia - expected_inertia) > 0.01:
		printerr("FAIL %s: center %s expected %s, inertia %.6f expected %.6f" %
				[name, center, expected_center, inertia, expected_inertia])
		return 1
	print("PASS %s: center=%s inertia=%.6f" % [name, center, inertia])
	return 0


func _run() -> void:
	var space: RID = PhysicsServer2D.space_create()
	var circle: RID = PhysicsServer2D.circle_shape_create()
	var rectangle: RID = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 1.0)
	PhysicsServer2D.shape_set_data(rectangle, Vector2(1.0, 1.0))

	var bodies: Array[RID] = []

	# A single radius-one disk of mass six has I = m * r^2 / 2 = 3.
	var single: RID = _make_body(space, 6.0, 0.0)
	PhysicsServer2D.body_add_shape(single, circle)
	bodies.append(single)

	# Two equal disks centered at x=0 and x=10:
	# I = 2 * (3 * 0.5 + 3 * 5^2) = 153.
	var double_circle: RID = _make_body(space, 6.0, 100.0)
	PhysicsServer2D.body_add_shape(double_circle, circle, Transform2D(0.0, Vector2()))
	PhysicsServer2D.body_add_shape(double_circle, circle, Transform2D(0.0, Vector2(10.0, 0.0)))
	bodies.append(double_circle)

	# Shape masses are weighted by area, not broadphase-padded AABBs.
	# The circle contributes PI area; the rectangle contributes 4.
	var mixed: RID = _make_body(space, 9.0, 200.0)
	PhysicsServer2D.body_add_shape(mixed, circle, Transform2D(0.0, Vector2()))
	PhysicsServer2D.body_add_shape(mixed, rectangle, Transform2D(0.0, Vector2(4.0, 0.0)))
	bodies.append(mixed)

	# Disabled shapes must not shift the mass center.
	var disabled: RID = _make_body(space, 6.0, 300.0)
	PhysicsServer2D.body_add_shape(disabled, circle)
	PhysicsServer2D.body_add_shape(disabled, circle, Transform2D(0.0, Vector2(10.0, 0.0)), true)
	bodies.append(disabled)

	# A user-supplied center is deliberately not recomputed.
	var manual: RID = _make_body(space, 6.0, 400.0)
	PhysicsServer2D.body_add_shape(manual, circle)
	PhysicsServer2D.body_set_param(manual, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS, Vector2(3.0, -2.0))
	bodies.append(manual)

	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var errors: int = 0
	errors += _check_mass(single, "single disk", Vector2(), 3.0)
	errors += _check_mass(double_circle, "two disks", Vector2(5.0, 0.0), 153.0)

	var area_sum: float = PI + 4.0
	var circle_mass: float = 9.0 * PI / area_sum
	var rectangle_mass: float = 9.0 * 4.0 / area_sum
	var center_x: float = rectangle_mass * 4.0 / 9.0
	var mixed_inertia: float = circle_mass * 0.5 + rectangle_mass * (2.0 / 3.0)
	mixed_inertia += circle_mass * center_x * center_x
	mixed_inertia += rectangle_mass * (4.0 - center_x) * (4.0 - center_x)
	errors += _check_mass(mixed, "area-weighted disk and rectangle", Vector2(center_x, 0.0), mixed_inertia)
	errors += _check_mass(disabled, "disabled shape", Vector2(), 3.0)
	errors += _check_mass(manual, "manual center of mass", Vector2(3.0, -2.0), 3.0 + 6.0 * 13.0)

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(rectangle)
	PhysicsServer2D.free_rid(space)

	if errors:
		printerr("Compound mass regression failed: %d case(s)." % errors)
		quit(1)
	else:
		print("Compound mass regression passed.")
		quit(0)
