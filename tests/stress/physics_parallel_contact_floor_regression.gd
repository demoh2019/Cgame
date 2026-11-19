# Contact-only large island with hundreds of boxes sharing a static floor.
# Compares the opt-in graph-color solver against the legacy sequential path.
# Run: godot --headless --path tests/stress --script res://physics_parallel_contact_floor_regression.gd
extends SceneTree

const BODY_COUNT := 320
const FRAMES := 45


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	for dimension in [2, 3]:
		for parallel in [false, true]:
			var result: Dictionary
			if dimension == 2:
				result = await _test_floor_2d(parallel)
			else:
				result = await _test_floor_3d(parallel)
			print("FLOOR_CONTACT_COLOR_RESULT:" + JSON.stringify({
				"dimension": dimension, "parallel": parallel, "result": result
			}))
			if result.has("error") or not bool(result.get("finite", false)):
				failures += 1
				printerr("FAIL: %dD contact coloring, parallel=%s: %s" %
						[dimension, parallel, result])
	if failures:
		quit(1)
	else:
		print("2D/3D static-floor contact coloring regression passed.")
		quit(0)


func _test_floor_2d(parallel: bool) -> Dictionary:
	const SETTING = "physics/2d/solver/parallel_large_islands"
	var saved_setting: Variant = ProjectSettings.get_setting(SETTING, false)
	ProjectSettings.set_setting(SETTING, parallel)
	var space: RID = PhysicsServer2D.space_create()
	ProjectSettings.set_setting(SETTING, saved_setting)

	var floor_shape: RID = PhysicsServer2D.rectangle_shape_create()
	var box_shape: RID = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(300.0, 0.5))
	PhysicsServer2D.shape_set_data(box_shape, Vector2(0.5, 0.5))

	var floor: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(floor, floor_shape)
	PhysicsServer2D.body_set_space(floor, space)

	var bodies: Array[RID] = []
	bodies.resize(BODY_COUNT)
	for i in range(BODY_COUNT):
		var body: RID = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, box_shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, -1.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		# Neighbors touch one another AND each box touches the same static floor.
		# The static floor cannot itself connect otherwise unrelated islands.
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2((float(i) - float(BODY_COUNT) / 2.0) * 0.95, -0.95)))
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body

	PhysicsServer2D.space_set_active(space, true)
	var finite := true
	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var accumulated_physics_ms := 0.0
	for frame in range(FRAMES):
		await physics_frame
		var frame_physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		peak_physics_ms = maxf(peak_physics_ms, frame_physics_ms)
		accumulated_physics_ms += frame_physics_ms
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for index in [0, int(BODY_COUNT / 2), BODY_COUNT - 1]:
			var body: RID = bodies[index]
			var state: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not state.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 1000000.0:
				finite = false
				break
		if not finite:
			break

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(box_shape)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)
	var result := {"finite": finite, "peak_pairs": peak_pairs, "bodies": BODY_COUNT,
			"peak_physics_ms": peak_physics_ms, "mean_physics_ms": accumulated_physics_ms / float(FRAMES)}
	# Floor contact alone does not connect bodies into an island. Require
	# many extra dynamic/dynamic contacts to exercise the large-island path.
	if peak_pairs < BODY_COUNT + int(BODY_COUNT / 2):
		result["error"] = "Too few dynamic/dynamic contact pairs for a large island"
	return result


func _test_floor_3d(parallel: bool) -> Dictionary:
	const SETTING = "physics/3d/solver/parallel_large_islands"
	var saved_setting: Variant = ProjectSettings.get_setting(SETTING, false)
	ProjectSettings.set_setting(SETTING, parallel)
	var space: RID = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(SETTING, saved_setting)

	var floor_shape: RID = PhysicsServer3D.box_shape_create()
	var box_shape: RID = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(300.0, 1.0, 10.0))
	PhysicsServer3D.shape_set_data(box_shape, Vector3(1.0, 1.0, 1.0))

	var floor: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_space(floor, space)

	var bodies: Array[RID] = []
	bodies.resize(BODY_COUNT)
	for i in range(BODY_COUNT):
		var body: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, box_shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3((float(i) - float(BODY_COUNT) / 2.0) * 0.95, 0.95, 0.0)))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body

	PhysicsServer3D.space_set_active(space, true)
	var finite := true
	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var accumulated_physics_ms := 0.0
	for frame in range(FRAMES):
		await physics_frame
		var frame_physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		peak_physics_ms = maxf(peak_physics_ms, frame_physics_ms)
		accumulated_physics_ms += frame_physics_ms
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for index in [0, int(BODY_COUNT / 2), BODY_COUNT - 1]:
			var body: RID = bodies[index]
			var state: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not state.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 1000000.0:
				finite = false
				break
		if not finite:
			break

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)
	var result := {"finite": finite, "peak_pairs": peak_pairs, "bodies": BODY_COUNT,
			"peak_physics_ms": peak_physics_ms, "mean_physics_ms": accumulated_physics_ms / float(FRAMES)}
	# Floor contact alone does not connect bodies into an island. Require
	# many extra dynamic/dynamic contacts to exercise the large-island path.
	if peak_pairs < BODY_COUNT + int(BODY_COUNT / 2):
		result["error"] = "Too few dynamic/dynamic contact pairs for a large island"
	return result
