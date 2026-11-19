# Regression test for the optional two-point normal contact block solver.
# Run: godot --headless --path tests/stress --script res://physics_block_solver_regression.gd
extends SceneTree


const BLOCK_SETTING := "physics/2d/solver/block_solver_enabled"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original: Variant = ProjectSettings.get_setting(BLOCK_SETTING, false)

	# Each new GodotSpace2D reads the setting at construction time.
	ProjectSettings.set_setting(BLOCK_SETTING, false)
	var sequential: Dictionary = await _simulate_stacks()
	ProjectSettings.set_setting(BLOCK_SETTING, true)
	var coupled: Dictionary = await _simulate_stacks()
	ProjectSettings.set_setting(BLOCK_SETTING, original)

	var errors: int = int(sequential["errors"]) + int(coupled["errors"])
	if int(sequential["peak_pairs"]) < 8 or int(coupled["peak_pairs"]) < 8:
		printerr("FAIL: stacked boxes did not generate sufficient collision pairs")
		errors += 1
	if int(sequential["settled"]) < 4 or int(coupled["settled"]) < 4:
		printerr("FAIL: too few base boxes settled on their platforms")
		errors += 1

	print("Sequential solver: %s" % sequential)
	print("Block solver: %s" % coupled)
	if errors != 0:
		printerr("2D block solver regression failed: %d error(s)" % errors)
		quit(1)
	else:
		print("2D block solver regression passed.")
		quit(0)


func _simulate_stacks() -> Dictionary:
	var space: RID = PhysicsServer2D.space_create()
	var floor_shape: RID = PhysicsServer2D.rectangle_shape_create()
	var box_shape: RID = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(42.0, 0.5))
	PhysicsServer2D.shape_set_data(box_shape, Vector2(0.8, 0.45))

	var floor: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(floor, floor_shape)
	PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, 0.7)
	PhysicsServer2D.body_set_space(floor, space)

	var bodies: Array[RID] = []
	var base_bodies: Array[RID] = []
	for column in range(8):
		var x: float = float(column - 4) * 9.0
		for level in range(4):
			var body: RID = PhysicsServer2D.body_create()
			PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
			PhysicsServer2D.body_add_shape(body, box_shape)
			PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, 0.7)
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
			# Default low-level space gravity points toward -Y. Reverse it so
			# test bodies above the platform actually settle onto it.
			PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, -1.0)
			var tilt: float = (0.02 if column % 2 == 0 else -0.02) if level == 3 else 0.0
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
					Transform2D(tilt, Vector2(x, -1.2 - float(level) * 0.99)))
			PhysicsServer2D.body_set_space(body, space)
			bodies.append(body)
			if level == 0:
				base_bodies.append(body)

	PhysicsServer2D.space_set_active(space, true)
	var errors: int = 0
	var peak_pairs: int = 0
	var maximum_speed_squared: float = 0.0
	for frame in range(240):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for body in bodies:
			var pose: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			var angular_velocity: float = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or is_nan(angular_velocity) or is_inf(angular_velocity):
				printerr("FAIL: non-finite body state at frame %d" % frame)
				errors += 1
				break
			maximum_speed_squared = maxf(maximum_speed_squared, velocity.length_squared())
			if velocity.length_squared() > 1000000.0 or absf(pose.origin.y) > 100.0:
				printerr("FAIL: runaway body at frame %d" % frame)
				errors += 1
				break
		if errors != 0:
			break

	var settled: int = 0
	for base in base_bodies:
		var pose: Transform2D = PhysicsServer2D.body_get_state(base, PhysicsServer2D.BODY_STATE_TRANSFORM)
		if absf(pose.origin.y + 0.95) < 0.55:
			settled += 1

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(box_shape)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)

	return {
		"errors": errors,
		"peak_pairs": peak_pairs,
		"settled": settled,
		"max_speed": sqrt(maximum_speed_squared),
	}
