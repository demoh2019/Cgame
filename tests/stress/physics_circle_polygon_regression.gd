# Regression coverage for the analytic circle/convex-polygon narrow phase.
# Run: godot --headless --path tests/stress --script res://physics_circle_polygon_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space: RID = PhysicsServer2D.space_create()
	var polygon: RID = PhysicsServer2D.convex_polygon_shape_create()
	var circle: RID = PhysicsServer2D.circle_shape_create()
	var body: RID = PhysicsServer2D.body_create()
	var vertices := PackedVector2Array([
		Vector2(-2.0, -2.0), Vector2(2.0, -2.0),
		Vector2(2.0, 2.0), Vector2(-2.0, 2.0)
	])

	PhysicsServer2D.shape_set_data(polygon, vertices)
	PhysicsServer2D.shape_set_data(circle, 0.5)
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, polygon)
	PhysicsServer2D.body_set_space(body, space)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
	var failures: int = 0
	if state == null:
		printerr("FAIL: no direct space state")
		failures = 1
	else:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape_rid = circle
		params.collide_with_bodies = true

		# Position, query margin, expected collision, description.
		var cases: Array = [
			[Vector2(2.25, 0.0), 0.0, true, "right exterior face"],
			[Vector2(-2.25, 0.0), 0.0, true, "left exterior face"],
			[Vector2(0.0, 2.25), 0.0, true, "bottom exterior face"],
			[Vector2(0.0, -2.25), 0.0, true, "top exterior face"],
			[Vector2(2.75, 0.0), 0.0, false, "separated face"],
			[Vector2(2.3, 2.3), 0.0, true, "convex vertex overlap"],
			[Vector2(2.4, 2.4), 0.0, false, "convex vertex separated"],
			[Vector2(-2.3, -2.3), 0.0, true, "opposite vertex overlap"],
			[Vector2(0.0, 0.0), 0.0, true, "embedded center SAT fallback"],
			[Vector2(2.0, 0.0), 0.0, true, "on edge SAT fallback"],
			[Vector2(2.55, 0.0), 0.10, true, "expanded margin overlap"],
			[Vector2(2.75, 0.0), 0.10, false, "expanded margin separated"],
		]
		for test_case in cases:
			params.transform = Transform2D(0.0, test_case[0])
			params.margin = test_case[1]
			var contacts: Array[Vector2] = state.collide_shape(params, 8)
			var collided: bool = not contacts.is_empty()
			if collided != test_case[2]:
				printerr("FAIL %s: expected %s, got %s" % [test_case[3], test_case[2], collided])
				failures += 1
			if collided and contacts.size() % 2 != 0:
				printerr("FAIL %s: unpaired contact points" % test_case[3])
				failures += 1

		# Rotated polygon tests use the polygon's real world-space transform.
		var rotation := PI / 5.0
		var polygon_transform := Transform2D(rotation, Vector2(3.0, -1.0))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, polygon_transform)
		await physics_frame
		var rotated_cases: Array = [
			[Vector2(2.25, 0.0), true, "rotated face overlap"],
			[Vector2(2.75, 0.0), false, "rotated face separated"],
			[Vector2(2.3, 2.3), true, "rotated vertex overlap"],
			[Vector2(2.4, 2.4), false, "rotated vertex separated"],
		]
		params.margin = 0.0
		for test_case in rotated_cases:
			params.transform = Transform2D(0.0, polygon_transform.xform(test_case[0]))
			var contacts: Array[Vector2] = state.collide_shape(params, 8)
			if (not contacts.is_empty()) != test_case[1]:
				printerr("FAIL %s" % test_case[2])
				failures += 1

		print("Checked %d circle-polygon regression cases." % (cases.size() + rotated_cases.size()))

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(polygon)
	PhysicsServer2D.free_rid(space)
	if failures > 0:
		printerr("Circle-polygon regression failures: %d" % failures)
		quit(1)
	else:
		print("Circle-polygon regression passed.")
		quit(0)
