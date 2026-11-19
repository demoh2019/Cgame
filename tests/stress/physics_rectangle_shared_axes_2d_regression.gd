# SAT duplicate-axis regression: equal-basis rectangles, rotated, scaled and different bases.
# Run: godot --headless --path tests/stress --script res://physics_rectangle_shared_axes_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer2D.space_create()
	var rect := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(rect, Vector2(2.0, 2.0))
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, rect)
	PhysicsServer2D.body_set_space(body, space)
	PhysicsServer2D.space_set_active(space, true)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape_rid = rect
	var failures := 0
	# Keep all pairs comfortably away from contact thresholds, including
	# nonzero query margins and slightly different basis directions.
	var cases := [
		{"offset": Vector2.ZERO, "hit": true},
		{"offset": Vector2(1.5, 0.0), "hit": true},
		{"offset": Vector2(-1.4, -1.2), "hit": true},
		{"offset": Vector2(1.2, 1.2), "hit": true},
		{"offset": Vector2(2.9, 0.0), "hit": false},
		{"offset": Vector2(0.0, -2.9), "hit": false},
		{"offset": Vector2(-2.9, 1.0), "hit": false},
	]
	for mode in range(4):
		# 0: identity, 1: equal rotation, 2: equal nonuniform scale,
		# 3: different rotations (four-axis general SAT fallback).
		var center := Vector2(float(mode) * 20.0, 0.0)
		var basis := Transform2D(0.37 if mode != 0 else 0.0, center)
		if mode == 2:
			basis = basis.scaled_local(Vector2(1.35, 0.8))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, basis)
		await physics_frame
		var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
		if state == null:
			printerr("FAIL: 2D rectangle direct state unavailable")
			failures += 1
			break
		for margin in [0.0, 0.03]:
			query.margin = margin
			for test_case in cases:
				var offset: Vector2 = test_case["offset"]
				var query_basis := Transform2D(basis.x, basis.y, basis.xform(offset))
				if mode == 3:
					query_basis = Transform2D(basis.x.rotated(0.31), basis.y.rotated(0.31), basis.xform(offset))
				query.transform = query_basis
				var intersects := not state.intersect_shape(query, 8).is_empty()
				if intersects != bool(test_case["hit"]):
					printerr("FAIL: rect SAT mode=%d margin=%s offset=%s expected=%s got=%s" %
							[mode, margin, offset, test_case["hit"], intersects])
					failures += 1
				if intersects and bool(test_case["hit"]):
					var contacts: PackedVector2Array = state.collide_shape(query, 8)
					if contacts.is_empty():
						printerr("FAIL: missing rectangle manifold at %s" % offset)
						failures += 1
					for point in contacts:
						if not point.is_finite():
							printerr("FAIL: non-finite rectangle contact %s" % point)
							failures += 1
							break

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(rect)
	PhysicsServer2D.free_rid(space)
	if failures == 0:
		print("Shared-basis rectangle SAT: identity, rotation, scale and relative rotation passed.")
	else:
		printerr("Shared-basis rectangle SAT: %d failures" % failures)
	quit(1 if failures > 0 else 0)
