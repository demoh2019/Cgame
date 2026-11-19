# High-damping 2D and 3D rigid-body benchmark, legacy vs Box2D-style.
# Run through tests/stress/run.py to get repeatability and peak RSS.
extends RefCounted


func run_2d(tree: SceneTree, scale: int, frames: int, implicit: bool) -> Dictionary:
	var setting := "physics/2d/solver/implicit_damping"
	var saved: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, implicit)
	var space := PhysicsServer2D.space_create()
	ProjectSettings.set_setting(setting, saved)
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.35)
	var count := mini(256 * scale, 4096)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var start := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 30.0)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 30.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(float(i % 128) * 4.0, float(int(i / 128)) * 4.0)))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(6.0, 0.0))
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 2.0)
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - start) / 1000.0
	PhysicsServer2D.space_set_active(space, true)
	var peak_physics_ms := 0.0
	var intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		await tree.physics_frame
		var tick := Time.get_ticks_usec()
		intervals.append(float(tick - last_tick) / 1000.0)
		last_tick = tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var linear: Vector2 = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var angular: float = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	if not linear.is_finite() or not (not is_nan(angular) and not is_inf(angular)):
		return {"error": "Non-finite 2D velocity after damping stress"}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"dimension": 2, "implicit_damping": implicit, "bodies": count,
		"physics_frames": frames, "creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
		"final_linear_speed": linear.length(), "final_angular_speed": absf(angular),
	}


func run_3d(tree: SceneTree, scale: int, frames: int, implicit: bool) -> Dictionary:
	var setting := "physics/3d/solver/implicit_damping"
	var saved: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, implicit)
	var space := PhysicsServer3D.space_create()
	ProjectSettings.set_setting(setting, saved)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.35)
	var count := mini(256 * scale, 4096)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var start := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 30.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 30.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(float(i % 64) * 4.0, float(int(i / 64) % 64) * 4.0, float(int(i / 4096)) * 4.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(6.0, 0.0, 0.0))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 0.0, 2.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - start) / 1000.0
	PhysicsServer3D.space_set_active(space, true)
	var peak_physics_ms := 0.0
	var intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		await tree.physics_frame
		var tick := Time.get_ticks_usec()
		intervals.append(float(tick - last_tick) / 1000.0)
		last_tick = tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var linear: Vector3 = PhysicsServer3D.body_get_state(bodies[0], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var angular: Vector3 = PhysicsServer3D.body_get_state(bodies[0], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	if not linear.is_finite() or not (angular.is_finite()):
		return {"error": "Non-finite 3D velocity after damping stress"}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"dimension": 3, "implicit_damping": implicit, "bodies": count,
		"physics_frames": frames, "creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
		"final_linear_speed": linear.length(), "final_angular_speed": angular.length(),
	}

