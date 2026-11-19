extends RefCounted
## One connected island with many pin joints, no contacts or SceneTree nodes.
## Both modes run the identical workload in separate physics spaces.


func run(tree: SceneTree, scale: int, frames: int, parallel: bool, high_priority: bool = false, extra_islands: int = 0, extra_island_size: int = 16, topology_churn: bool = false) -> Dictionary:
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

	# Additional disconnected chains exercise the island-first scheduler.
	# They have the same geometry in serial and parallel modes, and are
	# separated along Z so broadphase never joins the islands by contact.
	for island_id in range(extra_islands):
		var previous_body := RID()
		for i in range(extra_island_size):
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
			PhysicsServer3D.body_add_shape(body, sphere)
			PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
					Transform3D(Basis(), Vector3(float(i) * 3.0, 0.0, float(island_id + 1) * 20.0)))
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
					Vector3(0.0, 0.08 if i % 2 == 0 else -0.08, 0.0))
			PhysicsServer3D.body_set_space(body, space)
			bodies.append(body)
			if i > 0:
				var joint := PhysicsServer3D.joint_create()
				PhysicsServer3D.joint_make_pin(joint, previous_body, Vector3(1.5, 0.0, 0.0),
						body, Vector3(-1.5, 0.0, 0.0))
				joints.append(joint)
			previous_body = body
	var total_bodies := bodies.size()
	var total_joints := joints.size()
	var creation_ms := float(Time.get_ticks_usec() - creation_begin) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var error := ""
	for frame in range(frames):
		if topology_churn:
			# Replace an existing joint RID with new endpoints. The native
			# joint object may be reallocated at the same address, so cache
			# invalidation must compare body pointers as well as constraint IDs.
			if frame == 8:
				PhysicsServer3D.joint_make_pin(joints[100], bodies[100], Vector3(3.0, 0.0, 0.0),
						bodies[102], Vector3(-3.0, 0.0, 0.0))
			elif frame == 18:
				PhysicsServer3D.joint_make_pin(joints[100], bodies[100], Vector3(1.5, 0.0, 0.0),
						bodies[101], Vector3(-1.5, 0.0, 0.0))
			elif frame == 28:
				PhysicsServer3D.joint_set_solver_priority(joints[10], 2)
			elif frame == 34:
				PhysicsServer3D.joint_set_solver_priority(joints[10], 1)
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1], bodies[total_bodies - 1]]:
			var xform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not xform.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 10000.0:
				error = "Unstable 3D joint island on frame %d" % frame
				break
		if error != "":
			break

	# Joint anchors begin three meters apart. Large drift would indicate a
	# solver regression even when values remain finite.
	var max_joint_spacing := 0.0
	if error == "":
		for i in range(1, count):
			var previous: Transform3D = PhysicsServer3D.body_get_state(
					bodies[i - 1], PhysicsServer3D.BODY_STATE_TRANSFORM)
			var current: Transform3D = PhysicsServer3D.body_get_state(
					bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM)
			if not previous.origin.is_finite() or not current.origin.is_finite():
				error = "Non-finite 3D joint positions"
				break
			max_joint_spacing = maxf(max_joint_spacing, previous.origin.distance_to(current.origin))
		# Check the independent chains without comparing the gap *between*
		# distinct islands, which are deliberately far apart.
		for island_id in range(extra_islands):
			for i in range(1, extra_island_size):
				var index := count + island_id * extra_island_size + i
				var previous_extra: Transform3D = PhysicsServer3D.body_get_state(
						bodies[index - 1], PhysicsServer3D.BODY_STATE_TRANSFORM)
				var current_extra: Transform3D = PhysicsServer3D.body_get_state(
						bodies[index], PhysicsServer3D.BODY_STATE_TRANSFORM)
				if not previous_extra.origin.is_finite() or not current_extra.origin.is_finite():
					error = "Non-finite 3D independent-island joint positions"
					break
				max_joint_spacing = maxf(max_joint_spacing, previous_extra.origin.distance_to(current_extra.origin))
			if error != "":
				break
		if max_joint_spacing > 11.0:
			error = "Connected 3D island diverged (joint spacing > 11)"

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
	return {"bodies": total_bodies, "joints": total_joints, "parallel_large_islands": parallel,
			"extra_islands": extra_islands, "extra_island_size": extra_island_size,
			"high_priority_fallback": high_priority, "topology_churn": topology_churn, "physics_frames": frames,
			"creation_ms": creation_ms, "peak_physics_ms": peak_physics_ms,
			"max_joint_spacing": max_joint_spacing,
			"frame_interval_ms": stats, "frame_p95_ms": stats["p95"]}
