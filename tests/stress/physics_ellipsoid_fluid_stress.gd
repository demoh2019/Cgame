# Stress many transformed sphere shapes against optional fluid-plane buoyancy.
# Run via tests/stress/run.py --case physics_ellipsoid_fluid_3d_enabled
# Compare with physics_ellipsoid_fluid_3d_disabled at matching scale/frames.
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
	var prior := {}
	for key in options:
		prior[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, options[key])
	var space := PhysicsServer3D.space_create()
	for key in prior:
		ProjectSettings.set_setting(key, prior[key])
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var count := mini(64 * scale, 2048)
	var bodies: Array[RID] = []
	bodies.resize(count)
	var created := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		var rotation := Basis(Vector3(0, 0, 1), float(i % 13) * 0.13)
		var anisotropic := Basis.from_scale(Vector3(2.0, 1.0, 0.5))
		PhysicsServer3D.body_add_shape(body, sphere,
				Transform3D(rotation * anisotropic, Vector3.ZERO))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
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
	var creation_ms := float(Time.get_ticks_usec() - created) / 1000.0
	PhysicsServer3D.space_set_active(space, true)
	var intervals: Array[float] = []
	var tick_before := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var error := ""
	for _frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - tick_before) / 1000.0)
		tick_before = now
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1]]:
			var transform: Transform3D = PhysicsServer3D.body_get_state(
					body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(
					body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite():
				error = "Nonfinite affine ellipsoid fluid benchmark state"
				break
		if error != "":
			break
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)
	if error != "":
		return {"error": error}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"fluid_enabled": enabled,
		"ellipsoids": count,
		"physics_frames": frames,
		"creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
	}
