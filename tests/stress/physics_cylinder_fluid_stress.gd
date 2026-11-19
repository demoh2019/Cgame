# Scale sweep for rigid-body fluid-plane exact tilted cylinder integration.
# Compare the same 64-2048 cylinders with fluid-plane enabled/disabled.
# Invoked by tests/stress/run.py; prints physics p95 and resource metrics.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, enabled: bool) -> Dictionary:
	var options := {
		"physics/3d/fluid_plane/enabled": enabled,
		"physics/3d/fluid_plane/surface_height": 0.0,
		"physics/3d/fluid_plane/density": 1.0,
		"physics/3d/fluid_plane/drag_coefficient": 0.0,
		"physics/3d/fluid_plane/angular_drag": 0.0,
		"physics/3d/fluid_plane/flow_velocity": Vector3.ZERO,
		"physics/3d/solver/fluid_buoyancy": 0.0,
	}
	var old_settings: Dictionary = {}
	for key in options:
		old_settings[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, options[key])
	var space := PhysicsServer3D.space_create()
	for key in old_settings:
		ProjectSettings.set_setting(key, old_settings[key])
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var cylinder := PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(cylinder, {"radius": 0.5, "height": 4.0})
	var count := mini(64 * scale, 2048)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var started := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		var angle := float(i % 13) * 0.13
		PhysicsServer3D.body_add_shape(body, cylinder,
				Transform3D(Basis(Vector3(0, 0, 1), angle), Vector3.ZERO))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 10.0)
		PhysicsServer3D.body_set_collision_layer(body, 0)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % 64) * 8.0,
						float((i % 7) - 3) * 0.09, float(int(i / 64)) * 8.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
				Vector3(1, 0, 0))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, true)
	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var error := ""
	for _frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1]]:
			var pose: Transform3D = PhysicsServer3D.body_get_state(body,
					PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body,
					PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var omega: Vector3 = PhysicsServer3D.body_get_state(body,
					PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or not omega.is_finite():
				error = "Nonfinite tilted cylinder hydrostatic stress state"
				break
		if error != "":
			break
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(cylinder)
	PhysicsServer3D.free_rid(space)
	if error != "":
		return {"error": error}
	var statistics: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"fluid_enabled": enabled, "cylinders": count,
		"physics_frames": frames, "creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": statistics,
		"frame_p95_ms": statistics["p95"],
	}
