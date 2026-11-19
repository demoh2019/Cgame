# Compare the default depth-first and opt-in spread-preserving 3D manifolds.
# Run: godot --headless --path tests/stress --script res://physics_manifold_spread_3d_regression.gd
extends SceneTree


const COLUMNS := 8
const ROWS := 5
const FRAMES := 180


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy: Dictionary = await _run_case(false)
	var reduced: Dictionary = await _run_case(true)
	print("MANIFOLD_3D_LEGACY:" + JSON.stringify(legacy))
	print("MANIFOLD_3D_SPREAD:" + JSON.stringify(reduced))
	if not bool(legacy.get("valid", false)) or not bool(reduced.get("valid", false)):
		printerr("FAIL: 3D manifold spread regression failed")
		quit(1)
		return
	print("3D manifold spread regression passed.")
	quit(0)


func _run_case(enable_reduction: bool) -> Dictionary:
	var setting_path := "physics/3d/solver/manifold_spread_reduction"
	var original_setting: Variant = ProjectSettings.get_setting(setting_path, false)
	ProjectSettings.set_setting(setting_path, enable_reduction)
	var space := PhysicsServer3D.space_create()
	ProjectSettings.set_setting(setting_path, original_setting)

	var floor_shape := PhysicsServer3D.box_shape_create()
	var box_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(70, 1, 20))
	PhysicsServer3D.shape_set_data(box_shape, Vector3(1.2, 1.0, 1.2))

	var floor := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_space(floor, space)

	var bodies: Array[RID] = []
	for col in range(COLUMNS):
		for row in range(ROWS):
			var box := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(box, PhysicsServer3D.BODY_MODE_RIGID)
			PhysicsServer3D.body_add_shape(box, box_shape)
			PhysicsServer3D.body_set_param(box, PhysicsServer3D.BODY_PARAM_FRICTION, 0.8)
			PhysicsServer3D.body_set_state(box, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
			var pose := Transform3D(Basis(Vector3(0.0, 1.0, 0.0),
					0.05 if col % 2 == 0 else -0.05),
					Vector3((float(col) - float(COLUMNS) / 2.0) * 5.0,
					0.97 + float(row) * 0.98, 0.0))
			PhysicsServer3D.body_set_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
			PhysicsServer3D.body_set_space(box, space)
			bodies.append(box)

	PhysicsServer3D.space_set_active(space, true)
	var finite := true
	var peak_pairs := 0
	var max_speed_squared := 0.0
	var peak_physics_ms := 0.0
	for frame in range(FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs,
				int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms,
				float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		for body in bodies:
			var pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var speed: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not speed.is_finite() or speed.length_squared() > 1000000.0:
				finite = false
				break
			max_speed_squared = maxf(max_speed_squared, speed.length_squared())
		if not finite:
			break

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	return {
		"manifold_spread_reduction": enable_reduction,
		"bodies": bodies.size(), "frames": FRAMES,
		"peak_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"max_speed_squared": max_speed_squared,
		"valid": finite and peak_pairs >= COLUMNS * 2,
	}
