# Regression coverage for the analytic SegmentShape2D/CircleShape2D narrow phase.
# Run: ./bin/godot.<platform>.editor.<arch> --headless --path tests/stress \
#      --script res://physics_segment_circle_regression.gd
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space: RID = PhysicsServer2D.space_create()
	var segment: RID = PhysicsServer2D.segment_shape_create()
	var circle: RID = PhysicsServer2D.circle_shape_create()
	var body: RID = PhysicsServer2D.body_create()

	# Godot's segment shape takes Rect2(start, end), not a size vector.
	PhysicsServer2D.shape_set_data(segment, Rect2(Vector2(-2.0, 0.0), Vector2(2.0, 0.0)))
	PhysicsServer2D.shape_set_data(circle, 1.0)
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, segment)
	PhysicsServer2D.body_set_space(body, space)
	PhysicsServer2D.space_set_active(space, true)

	# Allow the broad phase to register the new body.
	await physics_frame
	await physics_frame

	var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
	var failures: int = 0
	if state == null:
		printerr("FAIL: no direct space state")
		failures = 1
	else:
		# Position, margin, expected collision, description.
		var cases: Array = [
			[Vector2(0.0, 0.75), 0.0, true, "segment side (top)"],
			[Vector2(0.0, -0.75), 0.0, true, "segment side (bottom)"],
			[Vector2(0.0, 1.25), 0.0, false, "separated side"],
			[Vector2(2.75, 0.0), 0.0, true, "right endpoint"],
			[Vector2(-2.75, 0.0), 0.0, true, "left endpoint"],
			[Vector2(3.25, 0.0), 0.0, false, "separated endpoint"],
			[Vector2(2.70, 0.70), 0.0, true, "rounded endpoint inside"],
			[Vector2(2.80, 0.80), 0.0, false, "rounded endpoint outside"],
			[Vector2(0.0, 0.0), 0.0, true, "coincident fallback"],
			[Vector2(0.0, 1.06), 0.10, true, "positive query margin"],
			[Vector2(0.0, 1.20), 0.10, false, "separated with margin"],
		]
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape_rid = circle
		params.collide_with_bodies = true
		for test_case in cases:
			params.transform = Transform2D(0.0, test_case[0])
			params.margin = test_case[1]
			var points: Array[Vector2] = state.collide_shape(params, 4)
			var collided: bool = not points.is_empty()
			if collided != test_case[2]:
				printerr("FAIL: %s: expected %s, got %s" % [test_case[3], test_case[2], collided])
				failures += 1
			if collided and points.size() % 2 != 0:
				printerr("FAIL: %s: contact points must be pairs" % test_case[3])
				failures += 1
		print("Checked %d segment-circle regression cases." % cases.size())

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(segment)
	PhysicsServer2D.free_rid(space)

	if failures > 0:
		printerr("Segment-circle regression failures: %d" % failures)
		quit(1)
	else:
		print("Segment-circle regression passed.")
		quit(0)
