# Regression tests for the capsule/capsule closest-segment narrow-phase shortcut.
# Run: godot --headless --path tests/stress --script res://physics_capsule_capsule_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space: RID = PhysicsServer2D.space_create()
	var capsule: RID = PhysicsServer2D.capsule_shape_create()
	var body: RID = PhysicsServer2D.body_create()

	# Capsule data is Vector2(radius, height).
	PhysicsServer2D.shape_set_data(capsule, Vector2(0.5, 4.0))
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, capsule)
	PhysicsServer2D.body_set_space(body, space)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var failures: int = 0
	var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
	if state == null:
		printerr("FAIL: unable to acquire 2D space state")
		failures += 1
	else:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape_rid = capsule
		params.collide_with_bodies = true
		# Angle, center, query margin, expected overlap, description.
		var cases: Array = [
			[0.0, Vector2(0.9, 0.0), 0.0, true, "parallel side overlap (SAT fallback)"],
			[0.0, Vector2(1.25, 0.0), 0.0, false, "parallel separated"],
			[0.0, Vector2(0.0, 3.2), 0.0, true, "parallel end-to-end overlap"],
			[PI * 0.5, Vector2(0.0, 0.0), 0.0, true, "crossing centerlines (SAT fallback)"],
			[PI * 0.5, Vector2(0.0, 2.25), 0.0, true, "perpendicular endcap overlap"],
			[PI * 0.5, Vector2(0.0, 2.75), 0.0, false, "perpendicular separated"],
			[PI * 0.5, Vector2(0.0, 2.55), 0.1, true, "contact through margin"],
			[PI * 0.5, Vector2(0.0, 2.70), 0.1, false, "margin still separated"],
			[0.005, Vector2(0.0, 0.0), 0.0, true, "near-parallel crossing"],
			[0.005, Vector2(1.5, 0.0), 0.0, false, "near-parallel separated"],
			[PI * 0.25, Vector2(5.0, 5.0), 0.0, false, "diagonal far apart"],
		]
		for test_case in cases:
			params.transform = Transform2D(test_case[0], test_case[1])
			params.margin = test_case[2]
			var points: Array[Vector2] = state.collide_shape(params, 8)
			var collided: bool = not points.is_empty()
			if collided != test_case[3]:
				printerr("FAIL: %s: expected %s, got %s" % [test_case[4], test_case[3], collided])
				failures += 1
			if collided and points.size() % 2 != 0:
				printerr("FAIL: %s: contact points are not paired" % test_case[4])
				failures += 1
		print("Checked %d capsule-capsule regression cases." % cases.size())

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(capsule)
	PhysicsServer2D.free_rid(space)
	if failures != 0:
		printerr("Capsule-capsule regression failures: %d" % failures)
		quit(1)
	else:
		print("Capsule-capsule regression passed.")
		quit(0)
