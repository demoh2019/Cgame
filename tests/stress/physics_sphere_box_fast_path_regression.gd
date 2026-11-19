# Verify sphere-box closest-point fast path, including interior and fallback transforms.
# Run: godot --headless --path tests/stress --script res://physics_sphere_box_fast_path_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	var box_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box_shape, Vector3.ONE * 2.0)
	var sphere_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere_shape, 0.4)
	var box_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(box_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(box_body, box_shape)
	PhysicsServer3D.body_set_space(box_body, space)
	PhysicsServer3D.space_set_active(space, true)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape_rid = sphere_shape
	query.margin = 0.0
	var failures := 0
	var cases := [
		{"center": Vector3.ZERO, "hit": true},
		{"center": Vector3(0.5, 0.0, 0.0), "hit": true},
		{"center": Vector3(1.2, 0.0, 0.0), "hit": true},
		{"center": Vector3(1.2, 1.2, 0.0), "hit": true},
		{"center": Vector3(-1.2, -1.2, 0.0), "hit": true},
		{"center": Vector3(1.8, 0.0, 0.0), "hit": false},
		{"center": Vector3(0.0, 0.0, -1.8), "hit": false},
		{"center": Vector3(1.8, 1.8, 0.0), "hit": false},
	]
	# Identity is the new path, rotation and nonuniform scale are the
	# pre-existing affine-inverse fallback. The shared unscaled local
	# coordinates give the same collision expectation in every case.
	var bases: Array[Basis] = [
		Basis(),
		Basis(Vector3.UP, 0.37),
		Basis().scaled(Vector3(1.5, 1.0, 1.0)),
	]
	for case_index in range(bases.size()):
		var basis: Basis = bases[case_index]
		var center := Vector3(float(case_index) * 20.0, 0.0, 0.0)
		PhysicsServer3D.body_set_state(box_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, center))
		await physics_frame
		var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
		if state == null:
			printerr("FAIL: sphere-box direct state unavailable")
			failures += 1
			break
		for test_case in cases:
			var local_offset: Vector3 = test_case["center"]
			query.transform = Transform3D(Basis(), center + basis * local_offset)
			var hit := not state.intersect_shape(query, 8).is_empty()
			var expected: bool = test_case["hit"]
			if hit != expected:
				printerr("FAIL: sphere-box case=%d center=%s expected=%s actual=%s" %
						[case_index, local_offset, expected, hit])
				failures += 1
			if expected and hit:
				var points: PackedVector3Array = state.collide_shape(query, 8)
				if points.is_empty():
					printerr("FAIL: missing sphere-box manifold at %s" % local_offset)
					failures += 1
				for point in points:
					if not point.is_finite():
						printerr("FAIL: nonfinite sphere-box contact at %s" % local_offset)
						failures += 1
						break

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(box_body)
	PhysicsServer3D.free_rid(sphere_shape)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(space)
	if failures == 0:
		print("Sphere-box identity, rotation and nonuniform-scale regression passed.")
	else:
		printerr("Sphere-box narrowphase regression failed: %d case(s)" % failures)
	quit(1 if failures > 0 else 0)
