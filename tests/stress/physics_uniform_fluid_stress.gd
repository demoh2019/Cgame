# Stress 2D/3D uniform buoyancy and quadratic drag versus disabled baseline.
# Run via tests/stress/run.py; reports physics CPU/frame p95 and RSS.
extends RefCounted


func _configure_fluid(is_3d: bool, enabled: bool) -> Dictionary:
	var root := "physics/3d/solver/" if is_3d else "physics/2d/solver/"
	var flow: Variant = Vector3(3.0, 0.0, 0.0) if is_3d else Vector2(3.0, 0.0)
	var config := {
		root + "fluid_linear_drag": 0.4 if enabled else 0.0,
		root + "fluid_angular_drag": 0.3 if enabled else 0.0,
		root + "fluid_buoyancy": 1.0 if enabled else 0.0,
		root + "fluid_flow_velocity": flow if enabled else (Vector3.ZERO if is_3d else Vector2.ZERO),
	}
	var old := {}
	for key in config.keys():
		old[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, config[key])
	return old


func _restore_settings(original: Dictionary) -> void:
	for key in original.keys():
		ProjectSettings.set_setting(key, original[key])


func run(tree: SceneTree, scale: int, frames: int, is_3d: bool, enabled: bool) -> Dictionary:
	if is_3d:
		return await _run_3d(tree, scale, frames, enabled)
	return await _run_2d(tree, scale, frames, enabled)


func _run_2d(tree: SceneTree, scale: int, frames: int, enabled: bool) -> Dictionary:
	var old := _configure_fluid(false, enabled)
	var space := PhysicsServer2D.space_create()
	_restore_settings(old)
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var count := mini(256 * scale, 4096)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var create_start := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i % 64) * 8.0, float(int(i / 64)) * 8.0)))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
				Vector2(8.0 + float(i % 5), -1.0))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 2.0)
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - create_start) / 1000.0
	PhysicsServer2D.space_set_active(space, true)

	var intervals: Array[float] = []
	var tick_before := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var error := ""
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - tick_before) / 1000.0)
		tick_before = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1]]:
			var pose: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			var angular: float = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or not is_finite(angular):
				error = "Nonfinite 2D fluid integration state"
				break
		if error != "":
			break
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	if error != "":
		return {"error": error}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"fluid_enabled": enabled, "dimensions": 2, "body_count": count,
		"physics_frames": frames, "creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
	}


func _run_3d(tree: SceneTree, scale: int, frames: int, enabled: bool) -> Dictionary:
	var old := _configure_fluid(true, enabled)
	var space := PhysicsServer3D.space_create()
	_restore_settings(old)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var count := mini(256 * scale, 4096)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var create_start := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % 64) * 8.0, 0.0, float(int(i / 64)) * 8.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
				Vector3(8.0 + float(i % 5), -1.0, 0.0))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 2.0, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - create_start) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var intervals: Array[float] = []
	var tick_before := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var error := ""
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - tick_before) / 1000.0)
		tick_before = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1]]:
			var pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var angular: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or not angular.is_finite():
				error = "Nonfinite 3D fluid integration state"
				break
		if error != "":
			break
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	if error != "":
		return {"error": error}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"fluid_enabled": enabled, "dimensions": 3, "body_count": count,
		"physics_frames": frames, "creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
	}
