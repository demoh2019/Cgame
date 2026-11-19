# Runtime regression for 3D contact warm starts across physics tick-rate changes.
# Run: godot --headless --path tests/stress --script res://physics_warmstart_timestep_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_ticks: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60

	var space := PhysicsServer3D.space_create()
	var floor_shape := PhysicsServer3D.box_shape_create()
	var ball_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(35.0, 1.0, 35.0))
	PhysicsServer3D.shape_set_data(ball_shape, 0.7)

	var floor := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_space(floor, space)

	var ball := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(ball, ball_shape)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.0)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(0.0, 2.0, 0.0)))
	PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_space(ball, space)
	PhysicsServer3D.space_set_active(space, true)

	var failures := 0
	var peak_speed := 0.0
	var peak_pairs := 0
	for frame in range(180):
		if frame == 50:
			# A 0.5 timestep ratio retains impulses with scaling.
			Engine.physics_ticks_per_second = 120
		elif frame == 85:
			# Material changes on a persistent contact must clamp old friction.
			PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_FRICTION, 0.05)
			PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
					Vector3(2.0, 0.0, 0.0))
		elif frame == 110:
			# A 4x timestep jump invalidates the accumulated impulse cache.
			Engine.physics_ticks_per_second = 30
		elif frame == 145:
			Engine.physics_ticks_per_second = 60

		await physics_frame
		var transform: Transform3D = PhysicsServer3D.body_get_state(
				ball, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var linear_velocity: Vector3 = PhysicsServer3D.body_get_state(
				ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var angular_velocity: Vector3 = PhysicsServer3D.body_get_state(
				ball, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		if not transform.origin.is_finite() or not linear_velocity.is_finite() or not angular_velocity.is_finite():
			printerr("FAIL: 3D physics state is non-finite on frame %d" % frame)
			failures += 1
			break
		peak_speed = maxf(peak_speed, linear_velocity.length())
		if peak_speed > 50.0 or transform.origin.y > 5.0 or transform.origin.y < -5.0:
			printerr("FAIL: 3D contact became unstable at frame %d" % frame)
			failures += 1
			break

	if peak_pairs == 0:
		printerr("FAIL: 3D contacts were not generated")
		failures += 1

	Engine.physics_ticks_per_second = original_ticks
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(ball)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(ball_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	print("3D warm-start timestep regression: peak_speed=%.3f, peak_pairs=%d" % [peak_speed, peak_pairs])
	quit(1 if failures > 0 else 0)
