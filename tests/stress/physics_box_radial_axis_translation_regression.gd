# Box/capsule and box/cylinder SAT contact geometry must be independent of
# the absolute world origin: the radial axis is relative to each shape axis.
# Run: godot --headless --path tests/stress --script res://physics_box_radial_axis_translation_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	var box_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box_shape, Vector3(2.0, 2.0, 2.0))
	var box_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(box_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(box_body, box_shape)
	PhysicsServer3D.body_set_space(box_body, space)

	var capsule := PhysicsServer3D.capsule_shape_create()
	var cylinder := PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(capsule, {"radius": 0.4, "height": 2.0})
	PhysicsServer3D.shape_set_data(cylinder, {"radius": 0.4, "height": 2.0})
	PhysicsServer3D.space_set_active(space, true)

	var query := PhysicsShapeQueryParameters3D.new()
	query.margin = 0.0
	var cases := [
		{"offset": Vector3(1.2, 0.0, 0.0), "hit": true},
		{"offset": Vector3(-1.2, 0.0, 0.0), "hit": true},
		{"offset": Vector3(1.2, 0.0, 1.2), "hit": true},
		{"offset": Vector3(0.0, 0.0, 0.0), "hit": true},
		{"offset": Vector3(1.8, 0.0, 0.0), "hit": false},
		{"offset": Vector3(1.35, 0.0, 1.35), "hit": false},
	]
	var world_origins := [
		Vector3.ZERO,
		Vector3(4096.0, -8192.0, 12288.0),
		Vector3(-16384.0, 8192.0, -4096.0),
	]
	var failures := 0
	for shape_rid in [capsule, cylinder]:
		query.shape_rid = shape_rid
		for rotated in [false, true]:
			var basis := Basis(Vector3.UP, 0.37) if rotated else Basis()
			var base_hit: Array[bool] = []
			var base_contact: Array[Vector3] = []
			for world_index in range(world_origins.size()):
				var origin: Vector3 = world_origins[world_index]
				PhysicsServer3D.body_set_state(box_body, PhysicsServer3D.BODY_STATE_TRANSFORM,
						Transform3D(basis, origin))
				await physics_frame
				var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
				if state == null:
					printerr("FAIL: no direct physics space for box radial-axis test")
					failures += 1
					break
				for case_index in range(cases.size()):
					var case: Dictionary = cases[case_index]
					query.transform = Transform3D(basis, origin + basis * case["offset"])
					var hit := not state.intersect_shape(query, 8).is_empty()
					var expected: bool = case["hit"]
					if hit != expected:
						printerr("FAIL: box radial SAT hit shape=%s rotated=%s origin=%s case=%s expected=%s got=%s" %
								[shape_rid, rotated, origin, case["offset"], expected, hit])
						failures += 1
					var contact := Vector3.ZERO
					if hit:
						var points: PackedVector3Array = state.collide_shape(query, 8)
						if points.size() < 2:
							printerr("FAIL: box radial SAT manifold empty")
							failures += 1
						else:
							contact = points[0] - points[1]
							for point in points:
								if not point.is_finite():
									printerr("FAIL: non-finite box radial SAT contact")
									failures += 1
									break
					if world_index == 0:
						base_hit.append(hit)
						base_contact.append(contact)
					else:
						if hit != base_hit[case_index]:
							printerr("FAIL: box radial SAT changed hit after world translation")
							failures += 1
						if hit and base_contact[case_index].length_squared() > 0.0001 and contact.length_squared() > 0.0001:
							# Contact positions are world-relative, but
							# penetration directions should remain aligned.
							if base_contact[case_index].normalized().dot(contact.normalized()) < 0.8:
								printerr("FAIL: translated box radial contact changed direction")
								failures += 1

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(box_body)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(capsule)
	PhysicsServer3D.free_rid(cylinder)
	PhysicsServer3D.free_rid(space)
	if failures == 0:
		print("Box-capsule/cylinder radial axes stay translation-invariant.")
	else:
		printerr("Box radial-axis regression failed: %d errors" % failures)
	quit(1 if failures > 0 else 0)
