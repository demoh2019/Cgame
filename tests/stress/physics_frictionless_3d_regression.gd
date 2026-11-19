# Regression for the 3D frictionless contact solver and material changes.
# Run: godot --headless --path tests/stress --script res://physics_frictionless_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	var floor_shape := PhysicsServer3D.box_shape_create()
	var ball_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(35.0, 1.0, 35.0))
	PhysicsServer3D.shape_set_data(ball_shape, 0.7)
	var floors: Array[RID] = []
	var balls: Array[RID] = []
	var starts: Array[float] = []

	# Independent tracks avoid extra contacts with bodies from other tracks.
	for i in range(3):
		var x := float(i - 1) * 100.0
		var floor := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(floor, floor_shape)
		PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
		PhysicsServer3D.body_set_state(floor, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(x, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(floor, space)
		floors.append(floor)

		var ball := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(ball, ball_shape)
		PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_FRICTION, 0.0 if i == 0 else 1.0)
		PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(x, 3.0, 0.0)))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(4.0, 0.0, 0.0))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_space(ball, space)
		balls.append(ball)
		starts.append(x)

	PhysicsServer3D.space_set_active(space, true)
	var failures := 0
	var peak_pairs := 0
	for frame in range(150):
		# Exercise a persistent collision pair when friction is removed,
		# so no cached tangent impulse may be applied on later steps.
		if frame == 65:
			PhysicsServer3D.body_set_param(balls[2], PhysicsServer3D.BODY_PARAM_FRICTION, 0.0)
			PhysicsServer3D.body_set_state(balls[2], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(3.0, 0.0, 0.0))
		if frame == 95:
			PhysicsServer3D.body_set_param(balls[2], PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for ball in balls:
			var transform: Transform3D = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 1000000.0:
				printerr("FAIL: unstable 3D contact on frame %d" % frame)
				failures += 1
				break
		if failures != 0:
			break

	if failures == 0:
		var free_slide: Transform3D = PhysicsServer3D.body_get_state(balls[0], PhysicsServer3D.BODY_STATE_TRANSFORM)
		var high_friction: Transform3D = PhysicsServer3D.body_get_state(balls[1], PhysicsServer3D.BODY_STATE_TRANSFORM)
		var free_displacement := free_slide.origin.x - starts[0]
		var friction_displacement := high_friction.origin.x - starts[1]
		if free_displacement <= friction_displacement + 0.5:
			printerr("FAIL: frictionless 3D body did not slide farther: %f vs %f" % [free_displacement, friction_displacement])
			failures += 1
		if peak_pairs < 2:
			printerr("FAIL: 3D collision pairs were not generated")
			failures += 1
		print("3D contacts: free=%.3f, friction=%.3f, peak_pairs=%d" % [free_displacement, friction_displacement, peak_pairs])

	PhysicsServer3D.space_set_active(space, false)
	for ball in balls:
		PhysicsServer3D.free_rid(ball)
	for floor in floors:
		PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(ball_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	if failures != 0:
		printerr("3D frictionless contact regression failed: %d error(s)" % failures)
		quit(1)
	else:
		print("3D frictionless contact regression passed.")
		quit(0)
