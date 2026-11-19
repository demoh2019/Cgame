# Regression coverage for 2D contact warm starting and frictionless solver paths.
# Run: godot --headless --path tests/stress --script res://physics_contact_solver_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Confirm the non-default warm-start coefficient is accepted by a new
	# space. ProjectSettings are restored before the standalone test exits.
	var warm_start_setting := "physics/2d/solver/warm_start_coefficient"
	var original_warm_start: Variant = ProjectSettings.get_setting(warm_start_setting, 1.0)
	ProjectSettings.set_setting(warm_start_setting, 0.65)

	# The new space has its own default area, initialized with the project's
	# 2D gravity. PhysicsServer2D does not expose a default-area RID getter.
	var space := PhysicsServer2D.space_create()

	var floor_shape := PhysicsServer2D.rectangle_shape_create()
	var ball_shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(35.0, 1.0))
	PhysicsServer2D.shape_set_data(ball_shape, 0.7)
	var floors: Array[RID] = []
	var balls: Array[RID] = []
	var starts: Array[float] = []

	# Widely separated tracks avoid interactions between independent test bodies.
	for i in range(3):
		var x: float = float(i - 1) * 100.0
		var floor := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(floor, floor_shape)
		PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, 1.0)
		PhysicsServer2D.body_set_state(floor, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(x, 0.0)))
		PhysicsServer2D.body_set_space(floor, space)
		floors.append(floor)

		var ball := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(ball, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(ball, ball_shape)
		PhysicsServer2D.body_set_param(ball, PhysicsServer2D.BODY_PARAM_FRICTION, 0.0 if i == 0 else 1.0)
		# Raw-space default gravity points toward -Y. Reverse it so the
		# circles above the floor actually collide with the floor.
		PhysicsServer2D.body_set_param(ball, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, -1.0)
		PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(x, -3.0)))
		PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(6.0, 0.0))
		PhysicsServer2D.body_set_state(ball, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_space(ball, space)
		balls.append(ball)
		starts.append(x)

	PhysicsServer2D.space_set_active(space, true)
	var original_ticks: int = Engine.physics_ticks_per_second
	var failures: int = 0
	var peak_pairs: int = 0
	for frame in range(150):
		# Exercise fractional, zero and restored material friction while a
		# contact persists. The warm-start tangent impulse must remain inside
		# the current Coulomb cone after each material change.
		if frame == 30:
			PhysicsServer2D.body_set_param(balls[2], PhysicsServer2D.BODY_PARAM_FRICTION, 0.2)
		if frame == 65:
			PhysicsServer2D.body_set_param(balls[2], PhysicsServer2D.BODY_PARAM_FRICTION, 0.0)
		if frame == 95:
			PhysicsServer2D.body_set_param(balls[2], PhysicsServer2D.BODY_PARAM_FRICTION, 1.0)

		# Change the global fixed timestep while keeping contact pairs alive.
		# 60->120 and back test dt ratios 1/2 and 2; 60->240 exercises the
		# safe cache reset after a larger timestep change.
		if frame == 40:
			Engine.physics_ticks_per_second = 120
		if frame == 80:
			Engine.physics_ticks_per_second = 60
		if frame == 110:
			Engine.physics_ticks_per_second = 240
		if frame == 125:
			Engine.physics_ticks_per_second = 60
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for ball in balls:
			var transform: Transform2D = PhysicsServer2D.body_get_state(ball, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(ball, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite():
				printerr("FAIL: non-finite contact state on frame %d" % frame)
				failures += 1
				break
			if velocity.length_squared() > 1000000.0:
				printerr("FAIL: unstable contact speed on frame %d" % frame)
				failures += 1
				break
		if failures > 0:
			break

	if failures == 0:
		var free_slide: Transform2D = PhysicsServer2D.body_get_state(balls[0], PhysicsServer2D.BODY_STATE_TRANSFORM)
		var high_friction: Transform2D = PhysicsServer2D.body_get_state(balls[1], PhysicsServer2D.BODY_STATE_TRANSFORM)
		var free_displacement: float = free_slide.origin.x - starts[0]
		var friction_displacement: float = high_friction.origin.x - starts[1]
		if free_displacement <= friction_displacement + 0.5:
			printerr("FAIL: frictionless track did not slide farther: %f vs %f" % [free_displacement, friction_displacement])
			failures += 1
		if peak_pairs < 2:
			printerr("FAIL: no persistent collision pairs observed")
			failures += 1
		print("Contact solver: free=%.3f, friction=%.3f, peak_pairs=%d" % [free_displacement, friction_displacement, peak_pairs])

	Engine.physics_ticks_per_second = original_ticks
	PhysicsServer2D.space_set_active(space, false)
	for ball in balls:
		PhysicsServer2D.free_rid(ball)
	for floor in floors:
		PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(ball_shape)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(warm_start_setting, original_warm_start)

	if failures > 0:
		printerr("Contact solver regression failed: %d error(s)" % failures)
		quit(1)
	else:
		print("Contact solver regression passed.")
		quit(0)
