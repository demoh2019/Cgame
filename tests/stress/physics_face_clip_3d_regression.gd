# Face/face 3D clipping regression, including empty intersection and complex faces.
# Run: godot --headless --path tests/stress --script res://physics_face_clip_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	var prism := PhysicsServer3D.convex_polygon_shape_create()
	var vertices := PackedVector3Array()
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var x := cos(angle) * 1.2
		var z := sin(angle) * 1.2
		vertices.append(Vector3(x, -0.5, z))
		vertices.append(Vector3(x, 0.5, z))
	PhysicsServer3D.shape_set_data(prism, vertices)
	var static_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(static_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(static_body, prism)
	PhysicsServer3D.body_set_space(static_body, space)
	PhysicsServer3D.space_set_active(space, true)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape_rid = prism
	var failures := 0
	var cases := [
		{"offset": Vector3(0.0, 0.75, 0.0), "hit": true},
		{"offset": Vector3(0.2, 0.75, -0.1), "hit": true},
		{"offset": Vector3(-0.6, 0.85, 0.2), "hit": true},
		{"offset": Vector3(0.0, 2.5, 0.0), "hit": false},
		{"offset": Vector3(3.0, 0.0, 0.0), "hit": false},
	]
	for orientation in range(3):
		# 0: parallel 12-gon faces, 1: relative Y rotation, 2: both
		# rotations share the same world basis.
		var basis := Basis(Vector3.UP, 0.32) if orientation == 2 else Basis()
		var query_basis := basis * Basis(Vector3.UP, 0.17) if orientation == 1 else basis
		var center := Vector3(float(orientation) * 10.0, 0.0, 0.0)
		PhysicsServer3D.body_set_state(static_body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(basis, center))
		await physics_frame
		var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
		if state == null:
			printerr("FAIL: PhysicsDirectSpaceState3D unavailable")
			failures += 1
			break
		for margin in [0.0, 0.03]:
			query.margin = margin
			for test_case in cases:
				var offset: Vector3 = test_case["offset"]
				query.transform = Transform3D(query_basis, center + basis * offset)
				var hit := not state.intersect_shape(query, 16).is_empty()
				if hit != bool(test_case["hit"]):
					printerr("FAIL: 3D face clip orientation=%d margin=%s offset=%s expected=%s got=%s" %
							[orientation, margin, offset, test_case["hit"], hit])
					failures += 1
				if hit and bool(test_case["hit"]):
					var contacts: PackedVector3Array = state.collide_shape(query, 16)
					if contacts.is_empty():
						printerr("FAIL: missing 3D face/face manifold at %s" % offset)
						failures += 1
					for point in contacts:
						if not point.is_finite():
							printerr("FAIL: nonfinite face contact")
							failures += 1
							break

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(static_body)
	PhysicsServer3D.free_rid(prism)
	PhysicsServer3D.free_rid(space)
	if failures == 0:
		print("3D face clipping regression passed for 12-gon hulls and separated cases.")
	else:
		printerr("3D face clipping regression: %d failures" % failures)
	quit(1 if failures > 0 else 0)
