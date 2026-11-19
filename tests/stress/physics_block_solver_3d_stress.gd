# Paired low-level 3D contact workload for opt-in two-point LCP solving.
# Each run uses a new physics space; no SceneTree RigidBody3D node overhead.
extends RefCounted


const SETTING := "physics/3d/solver/block_solver_enabled"


func run(tree: SceneTree, scale: int, frames: int, block_solver: bool) -> Dictionary:
	var previous_setting: Variant = ProjectSettings.get_setting(SETTING, false)
	ProjectSettings.set_setting(SETTING, block_solver)
	var space: RID = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(SETTING, previous_setting)

	var floor_shape: RID = PhysicsServer3D.box_shape_create()
	var box_shape: RID = PhysicsServer3D.box_shape_create()
	var columns: int = mini(16 * scale, 512)
	var levels: int = 4
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(float(columns) * 3.0, 0.25, 4.0))
	PhysicsServer3D.shape_set_data(box_shape, Vector3(0.7, 0.45, 0.6))

	var floor: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_FRICTION, 0.7)
	PhysicsServer3D.body_set_space(floor, space)

	var bodies: Array[RID] = []
	var lowest: Array[RID] = []
	for column in range(columns):
		var x: float = (float(column) - float(columns) * 0.5) * 4.0
		for level in range(levels):
			var body: RID = PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
			PhysicsServer3D.body_add_shape(body, box_shape)
			PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.7)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
			# Small alternating rotations exercise face/edge manifolds.
			var tilt: float = (0.04 if column % 2 == 0 else -0.04) if level % 2 == 0 else 0.0
			var pose := Transform3D(Basis(Vector3.FORWARD, tilt),
					Vector3(x, 0.85 + float(level) * 1.05, 0.0))
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
			PhysicsServer3D.body_set_space(body, space)
			bodies.append(body)
			if level == 0:
				lowest.append(body)

	PhysicsServer3D.space_set_active(space, true)
	var errors: int = 0
	var peak_pairs: int = 0
	var peak_physics_ms: float = 0.0
	var frame_intervals: Array[float] = []
	var previous_tick: int = Time.get_ticks_usec()
	for frame in range(frames):
		await tree.physics_frame
		var tick: int = Time.get_ticks_usec()
		frame_intervals.append(float(tick - previous_tick) / 1000.0)
		previous_tick = tick
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in bodies:
			var pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var angular_velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or not angular_velocity.is_finite():
				errors += 1
				break
			if velocity.length_squared() > 1000000.0 or absf(pose.origin.y) > 100.0:
				errors += 1
				break
		if errors > 0:
			break

	var settled: int = 0
	for base in lowest:
		var pose: Transform3D = PhysicsServer3D.body_get_state(base, PhysicsServer3D.BODY_STATE_TRANSFORM)
		if absf(pose.origin.y - 0.7) < 0.6:
			settled += 1

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	frame_intervals.sort()
	var p95: float = 0.0
	if not frame_intervals.is_empty():
		p95 = frame_intervals[int(ceil(float(frame_intervals.size()) * 0.95)) - 1]
	return {
		"block_solver": block_solver,
		"bodies": bodies.size(),
		"physics_frames": frames,
		"peak_collision_pairs": peak_pairs,
		"peak_physics_ms": peak_physics_ms,
		"frame_p95_ms": p95,
		"settled_base_bodies": settled,
		"failures": errors,
	}
