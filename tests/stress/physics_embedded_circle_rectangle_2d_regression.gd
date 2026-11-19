# Headless regression for Box2D-style embedded circle/rectangle narrowphase.
# Run: godot --headless --path tests/stress --script res://physics_embedded_circle_rectangle_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer2D.space_create()
	var box_shape := PhysicsServer2D.rectangle_shape_create()
	var circle_shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(box_shape, Vector2(1.0, 1.0))
	PhysicsServer2D.shape_set_data(circle_shape, 0.35)
	var box_body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(box_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(box_body, box_shape)
	PhysicsServer2D.body_set_space(box_body, space)
	PhysicsServer2D.space_set_active(space, true)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape_rid = circle_shape
	query.margin = 0.0
	var failures := 0
	var cases := [
		{"offset": Vector2.ZERO, "hit": true},
		{"offset": Vector2(0.75, 0.0), "hit": true},
		{"offset": Vector2(-0.75, -0.75), "hit": true},
		{"offset": Vector2(0.0, 0.9), "hit": true},
		{"offset": Vector2(1.08, 0.0), "hit": true},
		{"offset": Vector2(0.0, -1.15), "hit": true},
		{"offset": Vector2(1.8, 0.0), "hit": false},
		{"offset": Vector2(0.0, 1.8), "hit": false},
	]
	# Identity and rotation use the analytic fast path; non-uniform scale
	# must remain on the original generic SAT route.
	for mode in range(3):
		var rotation := 0.37 if mode == 1 else 0.0
		var basis := Transform2D(rotation, Vector2(float(mode) * 20.0, 0.0))
		if mode == 2:
			basis = basis.scaled_local(Vector2(1.5, 1.0))
		PhysicsServer2D.body_set_state(box_body, PhysicsServer2D.BODY_STATE_TRANSFORM, basis)
		await physics_frame
		var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
		if state == null:
			printerr("FAIL: 2D direct physics state unavailable")
			failures += 1
			break
		for test_case in cases:
			var local_offset: Vector2 = test_case["offset"]
			var world_center := basis.xform(local_offset)
			query.transform = Transform2D(0.0, world_center)
			var hit := not state.intersect_shape(query, 8).is_empty()
			if hit != bool(test_case["hit"]):
				printerr("FAIL: 2D circle/rectangle mode=%d local=%s expected=%s hit=%s" %
						[mode, local_offset, test_case["hit"], hit])
				failures += 1
			if hit and bool(test_case["hit"]):
				var points: PackedVector2Array = state.collide_shape(query, 8)
				if points.is_empty():
					printerr("FAIL: missing embedded circle/rectangle contact at %s" % local_offset)
					failures += 1
				for point in points:
					if not point.is_finite():
						printerr("FAIL: non-finite 2D embedded circle contact")
						failures += 1
						break

	# A contained rigid circle should get pushed towards its closest exit
	# face, rather than further into the rectangle.
	PhysicsServer2D.body_set_state(box_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	var dynamic_circle := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(dynamic_circle, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(dynamic_circle, circle_shape)
	PhysicsServer2D.body_set_param(dynamic_circle, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_state(dynamic_circle, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(dynamic_circle, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(0.75, 0.0)))
	PhysicsServer2D.body_set_space(dynamic_circle, space)
	for frame in range(20):
		await physics_frame
	var exit_pose: Transform2D = PhysicsServer2D.body_get_state(dynamic_circle, PhysicsServer2D.BODY_STATE_TRANSFORM)
	if not exit_pose.origin.is_finite() or exit_pose.origin.x < 0.77:
		printerr("FAIL: embedded circle did not move towards nearest +X exit: %s" % exit_pose.origin)
		failures += 1

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(dynamic_circle)
	PhysicsServer2D.free_rid(box_body)
	PhysicsServer2D.free_rid(circle_shape)
	PhysicsServer2D.free_rid(box_shape)
	PhysicsServer2D.free_rid(space)
	if failures == 0:
		print("Embedded circle/rectangle 2D manifolds and exit direction passed.")
	else:
		printerr("Embedded circle/rectangle 2D regression failed: %d error(s)" % failures)
	quit(1 if failures > 0 else 0)
