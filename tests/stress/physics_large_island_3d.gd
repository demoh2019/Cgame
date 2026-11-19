extends RefCounted
## One connected island with many pin joints, no contacts or SceneTree nodes.
## Both modes run the identical workload in separate physics spaces.


func run(tree: SceneTree, scale: int, frames: int, parallel: bool, high_priority: bool = false) -> Dictionary:
	var setting_path := "physics/3d/solver/parallel_large_islands"
	var saved_setting: Variant = ProjectSettings.get_setting(setting_path)
	ProjectSettings.set_setting(setting_path, parallel)
	var space := PhysicsServer3D.space_create()
	# The space cached the setting; do not affect subsequent stress scenarios.
	ProjectSettings.set_setting(setting_path, saved_setting)

	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.4)
	var count := mini(320 * scale, 3840)
	var bodies: Array[RID] = []
	var joints: Array[RID] = []
	bodies.resize(count)
	joints.resize(count - 1)

	var creation_begin := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, sphere)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i) * 3.0, 0.0, 0.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
				Vector3(0.0, 0.08 if i % 2 == 0 else -0.08, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	for i in range(1, count):
		var joint := PhysicsServer3D.joint_create()
		PhysicsServer3D.joint_make_pin(joint, bodies[i - 1], Vector3(1.5, 0.0, 0.0),
				bodies[i], Vector3(-1.5, 0.0, 0.0))
		if high_priority and i == 1:
			# Must opt out of colored parallel solving for priority > 1.
			PhysicsServer3D.joint_set_solver_priority(joint, 2)
		joints[i - 1] = joint
	var creation_ms := float(Time.get_ticks_usec() - creation_begin) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var error := ""
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1]]:
			var xform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not xform.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 10000.0:
				error = "Unstable 3D joint island on frame %d" % frame
				break
		if error != "":
			break

	PhysicsServer3D.space_set_active(space, false)
	for joint in joints:
		PhysicsServer3D.free_rid(joint)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	joints.clear()
	bodies.clear()
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)

	if error != "":
		return {"error": error}
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	return {"bodies": count, "joints": count - 1, "parallel_large_islands": parallel,
			"high_priority_fallback": high_priority, "physics_frames": frames,
			"creation_ms": creation_ms, "peak_physics_ms": peak_physics_ms,
			"frame_interval_ms": stats, "frame_p95_ms": stats["p95"]}
