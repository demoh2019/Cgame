# Run with the built-in GodotPhysics3D backend:
# godot --headless --path tests/stress --script res://physics_substeps_3d_regression.gd
#
# physics/3d/solver/substeps simulates every physics tick as N shorter steps. It must
#  * keep a tall box stack standing that collapses with the plain 16 iterations,
#  * give a force applied for one tick exactly one tick of impulse (not N, not 1/N),
#  * let a moving kinematic platform carry a body at the platform speed,
#  * report the whole tick from PhysicsDirectBodyState3D.get_step().
extends SceneTree

const SETTING_SUBSTEPS := "physics/3d/solver/substeps"
const SETTING_ITERATIONS := "physics/3d/solver/solver_iterations"
const STACK_HEIGHT := 20
const STACK_FRAMES := 360


func _initialize() -> void:
	_run.call_deferred()


func _make_space(substeps: int, iterations: int, gravity: float, damped: bool = true) -> RID:
	var saved_substeps: Variant = ProjectSettings.get_setting(SETTING_SUBSTEPS, 1)
	var saved_iterations: Variant = ProjectSettings.get_setting(SETTING_ITERATIONS, 16)
	ProjectSettings.set_setting(SETTING_SUBSTEPS, substeps)
	ProjectSettings.set_setting(SETTING_ITERATIONS, iterations)
	# GodotSpace3D reads both settings when it is created.
	var space := PhysicsServer3D.space_create()
	ProjectSettings.set_setting(SETTING_SUBSTEPS, saved_substeps)
	ProjectSettings.set_setting(SETTING_ITERATIONS, saved_iterations)
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, gravity)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(0, -1, 0))
	# Default damping stays on for the stack and platform cases (it is part of normal behavior);
	# the force test turns it off so the velocity is exactly F / m * dt.
	if not damped:
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP, 0.0)
	return space


func _free_all(space: RID, rids: Array) -> void:
	PhysicsServer3D.space_set_active(space, false)
	for rid in rids:
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.free_rid(space)


func _stack(substeps: int, iterations: int) -> Dictionary:
	var space := _make_space(substeps, iterations, 9.8)
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(20, 1, 20))
	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -1, 0)))
	PhysicsServer3D.body_set_space(floor_body, space)
	var box_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box_shape, Vector3(0.5, 0.5, 0.5))
	var boxes: Array = []
	for i in STACK_HEIGHT:
		var box := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(box, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(box, box_shape)
		PhysicsServer3D.body_set_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0.5 + i, 0)))
		PhysicsServer3D.body_set_space(box, space)
		boxes.append(box)
	for frame in STACK_FRAMES:
		await physics_frame
	var top: Transform3D = PhysicsServer3D.body_get_state(boxes[STACK_HEIGHT - 1], PhysicsServer3D.BODY_STATE_TRANSFORM)
	var max_drift := 0.0
	for box in boxes:
		var origin: Vector3 = (PhysicsServer3D.body_get_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin
		max_drift = maxf(max_drift, Vector2(origin.x, origin.z).length())
	var result := {"substeps": substeps, "iterations": iterations, "top_y": top.origin.y, "max_drift": max_drift}
	var rids: Array = boxes.duplicate()
	rids.append_array([floor_body, floor_shape, box_shape])
	_free_all(space, rids)
	return result


func _force_impulse(substeps: int) -> Dictionary:
	var space := _make_space(substeps, 16, 0.0, false)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 2.0)
	PhysicsServer3D.body_set_space(body, space)
	await physics_frame
	PhysicsServer3D.body_apply_central_force(body, Vector3(10, 0, 0))
	await physics_frame
	await physics_frame
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	# F / m * dt for one tick, and the force must not be applied again on the next tick.
	var expected := 10.0 / 2.0 / float(Engine.physics_ticks_per_second)
	var result := {"substeps": substeps, "vx": velocity.x, "expected": expected}
	_free_all(space, [body, shape])
	return result


func _kinematic_carry(substeps: int) -> Dictionary:
	var space := _make_space(substeps, 16, 9.8)
	var platform_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(platform_shape, Vector3(20, 0.5, 5))
	var platform := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(platform, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_add_shape(platform, platform_shape)
	PhysicsServer3D.body_set_param(platform, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_state(platform, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -0.5, 0)))
	PhysicsServer3D.body_set_space(platform, space)
	var box_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box_shape, Vector3(0.5, 0.5, 0.5))
	var box := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(box, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(box, box_shape)
	PhysicsServer3D.body_set_param(box, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0.51, 0)))
	PhysicsServer3D.body_set_space(box, space)

	const PLATFORM_SPEED := 2.0
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var platform_x := 0.0
	var box_start := 0.0
	for frame in 120:
		platform_x += PLATFORM_SPEED * tick
		PhysicsServer3D.body_set_state(platform, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(platform_x, -0.5, 0)))
		await physics_frame
		if frame == 29:
			box_start = (PhysicsServer3D.body_get_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin.x
	var box_x: float = (PhysicsServer3D.body_get_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin.x
	var travelled := (box_x - box_start) / (90.0 * tick)
	var result := {"substeps": substeps, "box_speed": travelled, "platform_speed": PLATFORM_SPEED,
			"platform_x": (PhysicsServer3D.body_get_state(platform, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin.x}
	_free_all(space, [box, box_shape, platform, platform_shape])
	return result


func _run() -> void:
	var ok := true

	# 1. Stack stability: same iteration budget per tick (16), spent differently.
	var plain: Dictionary = await _stack(1, 16)
	var sub4: Dictionary = await _stack(4, 4)
	print("SUBSTEPS_STACK_PLAIN:" + JSON.stringify(plain))
	print("SUBSTEPS_STACK_4x4:" + JSON.stringify(sub4))
	var ideal_top := 0.5 + float(STACK_HEIGHT - 1)
	ok = ok and float(plain["top_y"]) < ideal_top - 5.0  # Documents the weakness being fixed.
	ok = ok and absf(float(sub4["top_y"]) - ideal_top) < 0.8 and float(sub4["max_drift"]) < 0.8

	# 2. A force applied for one tick gives one tick of impulse, independent of the substep count.
	for substeps in [1, 4]:
		var force: Dictionary = await _force_impulse(substeps)
		print("SUBSTEPS_FORCE:" + JSON.stringify(force))
		ok = ok and absf(float(force["vx"]) - float(force["expected"])) < float(force["expected"]) * 0.05

	# 3. A kinematic platform carries a box at its own speed, with or without substeps.
	for substeps in [1, 4]:
		var carry: Dictionary = await _kinematic_carry(substeps)
		print("SUBSTEPS_KINEMATIC:" + JSON.stringify(carry))
		ok = ok and absf(float(carry["box_speed"]) - float(carry["platform_speed"])) < 0.3

	if ok:
		print("3D substeps regression passed.")
		quit(0)
	else:
		printerr("FAIL: 3D substeps regression")
		quit(1)
