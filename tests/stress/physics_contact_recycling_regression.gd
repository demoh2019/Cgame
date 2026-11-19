# Regression test for 2D persistent contact matching during corner rotation/sliding.
# Run: godot --headless --path tests/stress --script res://physics_contact_recycling_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space: RID = PhysicsServer2D.space_create()
	var floor_shape: RID = PhysicsServer2D.rectangle_shape_create()
	var box_shape: RID = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(8.0, 0.5))
	PhysicsServer2D.shape_set_data(box_shape, Vector2(0.9, 0.6))

	var floors: Array[RID] = []
	var boxes: Array[RID] = []
	for i in range(12):
		var x: float = float(i) * 32.0

		var floor: RID = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(floor, floor_shape)
		PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, 0.8)
		PhysicsServer2D.body_set_state(floor, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(x, 0.0)))
		PhysicsServer2D.body_set_space(floor, space)
		floors.append(floor)

		var box: RID = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(box, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(box, box_shape)
		PhysicsServer2D.body_set_param(box, PhysicsServer2D.BODY_PARAM_FRICTION, 0.8)
		PhysicsServer2D.body_set_state(box, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		var angle: float = 0.12 if i % 2 == 0 else -0.12
		PhysicsServer2D.body_set_state(box, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(angle, Vector2(x, -2.5)))
		PhysicsServer2D.body_set_state(box, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(0.35 if i % 2 == 0 else -0.35, 0.0))
		PhysicsServer2D.body_set_state(box, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.35 if i % 2 == 0 else -0.35)
		PhysicsServer2D.body_set_space(box, space)
		boxes.append(box)

	PhysicsServer2D.space_set_active(space, true)
	var failures: int = 0
	var peak_pairs: int = 0
	var peak_speed_squared: float = 0.0
	for frame in range(240):
		# Reverse angular motion periodically to exercise changing manifold
		# ordering, where two cached anchors can be close to one another.
		if frame == 60 or frame == 120 or frame == 180:
			for i in range(boxes.size()):
				var angular_velocity: float = PhysicsServer2D.body_get_state(boxes[i], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
				PhysicsServer2D.body_set_state(boxes[i], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, -angular_velocity)

		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for i in range(boxes.size()):
			var pose: Transform2D = PhysicsServer2D.body_get_state(boxes[i], PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(boxes[i], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			var angular_velocity: float = PhysicsServer2D.body_get_state(boxes[i], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or not is_finite(angular_velocity):
				printerr("FAIL: non-finite state for box %d at frame %d" % [i, frame])
				failures += 1
				break
			peak_speed_squared = maxf(peak_speed_squared, velocity.length_squared())
			if velocity.length_squared() > 1000000.0 or absf(pose.origin.x - float(i) * 32.0) > 50.0:
				printerr("FAIL: runaway contact state for box %d at frame %d" % [i, frame])
				failures += 1
				break
		if failures > 0:
			break

	if peak_pairs < 6:
		printerr("FAIL: insufficient persistent contact pairs (%d)" % peak_pairs)
		failures += 1
	print("Recycling regression: peak_pairs=%d peak_speed_squared=%.3f" % [peak_pairs, peak_speed_squared])

	PhysicsServer2D.space_set_active(space, false)
	for box in boxes:
		PhysicsServer2D.free_rid(box)
	for floor in floors:
		PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(box_shape)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)

	if failures == 0:
		print("Contact recycling regression passed.")
		quit(0)
	else:
		printerr("Contact recycling regression failures: %d" % failures)
		quit(1)
