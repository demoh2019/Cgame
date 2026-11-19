# Low-level large-island benchmark shared by stress runner and regression.
# Builds one connected pin-joint chain, avoiding SceneTree node overhead.
extends RefCounted


const PARALLEL_SETTING := "physics/2d/solver/parallel_large_islands"


func run(tree: SceneTree, scale: int, frames: int, parallel: bool) -> Dictionary:
	var original_setting: Variant = ProjectSettings.get_setting(PARALLEL_SETTING, false)
	ProjectSettings.set_setting(PARALLEL_SETTING, parallel)
	# The setting is captured by GodotSpace2D at creation time.
	var space: RID = PhysicsServer2D.space_create()
	ProjectSettings.set_setting(PARALLEL_SETTING, original_setting)

	var shape: RID = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.25)
	var count: int = mini(384 * scale, 6144)
	var spacing := 1.2
	var bodies: Array[RID] = []
	var joints: Array[RID] = []
	bodies.resize(count)
	joints.resize(count - 1)

	var begin_create: int = Time.get_ticks_usec()
	for i in range(count):
		var body: RID = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i) * spacing, 0.0)))
		if i % 19 == 0:
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
					Vector2(0.0, 0.2 if i % 2 == 0 else -0.2))
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body

		if i > 0:
			var joint: RID = PhysicsServer2D.joint_create()
			PhysicsServer2D.joint_make_pin(joint, Vector2((float(i) - 0.5) * spacing, 0.0),
					bodies[i - 1], body)
			joints[i - 1] = joint

	var creation_ms: float = float(Time.get_ticks_usec() - begin_create) / 1000.0
	PhysicsServer2D.space_set_active(space, true)
	var peak_physics_ms: float = 0.0
	var frame_intervals: Array[float] = []
	var previous_tick: int = Time.get_ticks_usec()
	var valid: bool = true
	for frame in range(frames):
		await tree.physics_frame
		var now: int = Time.get_ticks_usec()
		frame_intervals.append(float(now - previous_tick) / 1000.0)
		previous_tick = now
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for index in [0, int(count / 2), count - 1]:
			var pose: Transform2D = PhysicsServer2D.body_get_state(bodies[index], PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(bodies[index], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 10000.0:
				valid = false
				break
		if not valid:
			break

	var max_joint_gap: float = 0.0
	if valid:
		for i in range(1, count):
			var a: Transform2D = PhysicsServer2D.body_get_state(bodies[i - 1], PhysicsServer2D.BODY_STATE_TRANSFORM)
			var b: Transform2D = PhysicsServer2D.body_get_state(bodies[i], PhysicsServer2D.BODY_STATE_TRANSFORM)
			if not a.origin.is_finite() or not b.origin.is_finite():
				valid = false
				break
			max_joint_gap = maxf(max_joint_gap, a.origin.distance_to(b.origin))
		if max_joint_gap > spacing + 8.0:
			valid = false

	PhysicsServer2D.space_set_active(space, false)
	# Joints must be destroyed before their bodies.
	for joint in joints:
		PhysicsServer2D.free_rid(joint)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)

	var frame_stats: Dictionary = _frame_statistics(frame_intervals)
	return {
		"bodies": count,
		"joints": count - 1,
		"parallel_large_islands": parallel,
		"frames": frames,
		"creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": frame_stats,
		"frame_p95_ms": frame_stats["p95"],
		"max_joint_gap": max_joint_gap,
		"valid": valid
	}


func _frame_statistics(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"p50": 0.0, "p95": 0.0, "max": 0.0}
	var ordered := samples.duplicate()
	ordered.sort()
	var median: float = ordered[int((ordered.size() - 1) * 0.5)]
	var p95: float = ordered[int(ceil(float(ordered.size()) * 0.95)) - 1]
	return {"p50": median, "p95": p95, "max": ordered[ordered.size() - 1]}
