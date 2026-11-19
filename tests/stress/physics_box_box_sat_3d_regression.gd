# Axis-aligned box-box SAT: compare the 3-axis fast path with rotated fallback.
# Run: godot --headless --path tests/stress --script res://physics_box_box_sat_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	var box := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box, Vector3(2.0, 2.0, 2.0))
	var static_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(static_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(static_body, box)
	PhysicsServer3D.body_set_space(static_body, space)
	PhysicsServer3D.space_set_active(space, true)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape_rid = box
	query.margin = 0.0
	var failures := 0
	# Well away from touching thresholds: each case is unequivocally
	# overlapping or separated along at least one world-space box axis.
	var cases := [
		{"offset": Vector3(1.50, 0.0, 0.0), "hit": true},
		{"offset": Vector3(1.75, 1.75, 0.0), "hit": true},
		{"offset": Vector3(-1.50, -1.25, -1.75), "hit": true},
		{"offset": Vector3(0.0, 0.0, 0.0), "hit": true},
		{"offset": Vector3(2.50, 0.0, 0.0), "hit": false},
		{"offset": Vector3(1.50, 2.50, 0.0), "hit": false},
		{"offset": Vector3(-2.50, 1.25, 1.25), "hit": false},
		{"offset": Vector3(0.0, 0.0, 2.50), "hit": false},
	]

	for rotated in [false, true]:
		var basis := Basis(Vector3.UP, 0.37) if rotated else Basis()
		PhysicsServer3D.body_set_state(static_body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(basis, Vector3.ZERO))
		await physics_frame
		var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
		if state == null:
			failures += 1
			printerr("FAIL: 3D direct physics space unavailable")
			break
		for test_case in cases:
			query.transform = Transform3D(basis, basis * test_case["offset"])
			var results: Array[Dictionary] = state.intersect_shape(query, 8)
			var hit := not results.is_empty()
			if hit != bool(test_case["hit"]):
				printerr("FAIL: 3D box-box SAT rotated=%s offset=%s expected=%s got=%s" %
						[rotated, test_case["offset"], test_case["hit"], hit])
				failures += 1
			# The actual SAT manifold is also exercised, not just AABB
			# broadphase overlap.
			if hit and test_case["offset"] != Vector3.ZERO:
				var contact_points: PackedVector3Array = state.collide_shape(query, 8)
				if contact_points.is_empty():
					printerr("FAIL: box-box manifold missing at offset %s" % test_case["offset"])
					failures += 1
				else:
					for point in contact_points:
						if not point.is_finite():
							printerr("FAIL: nonfinite box-box contact")
							failures += 1
							break

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(static_body)
	PhysicsServer3D.free_rid(box)
	PhysicsServer3D.free_rid(space)
	if failures == 0:
		print("Axis-aligned and rotated 3D box-box SAT regression passed.")
	else:
		printerr("3D box-box SAT regression: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
