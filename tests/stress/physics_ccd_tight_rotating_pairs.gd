extends RefCounted
## Compare angular CCD broadphase proxy cost on an identical workload.
## Each thin spinning rigid body has a nearby static blocker just outside
## its actual circle of rotation, but within the legacy radial proxy.
## All bodies have CCD enabled, zero gravity/damping and no true contacts.


func run(tree: SceneTree, scale: int, frames: int, dimension: int, tight: bool) -> Dictionary:
	if dimension == 2:
		return await _run_2d(tree, scale, frames, tight)
	return await _run_3d(tree, scale, frames, tight)


func _run_2d(tree: SceneTree, scale: int, frames: int, tight: bool) -> Dictionary:
	const ROT_SETTING := "physics/2d/solver/ccd_rotational_bounds"
	const TIGHT_SETTING := "physics/2d/solver/ccd_tight_rotational_bounds"
	var old_rot: Variant = ProjectSettings.get_setting(ROT_SETTING, false)
	var old_tight: Variant = ProjectSettings.get_setting(TIGHT_SETTING, false)
	ProjectSettings.set_setting(ROT_SETTING, true)
	ProjectSettings.set_setting(TIGHT_SETTING, tight)
	var space: RID = PhysicsServer2D.space_create()
	ProjectSettings.set_setting(ROT_SETTING, old_rot)
	ProjectSettings.set_setting(TIGHT_SETTING, old_tight)

	var count := mini(64 * scale, 4096)
	var rod_shape: RID = PhysicsServer2D.rectangle_shape_create()
	var blocker_shape: RID = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(rod_shape, Vector2(10.0, 0.1))
	PhysicsServer2D.shape_set_data(blocker_shape, Vector2(0.1, 0.1))
	var rods: Array[RID] = []
	var blockers: Array[RID] = []
	rods.resize(count)
	blockers.resize(count)
	for i in range(count):
		var origin := Vector2(float(i % 64) * 60.0, float(int(i / 64)) * 60.0)
		var blocker: RID = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(blocker, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(blocker, blocker_shape)
		PhysicsServer2D.body_set_state(blocker, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, origin + Vector2(10.45, 0.0)))
		PhysicsServer2D.body_set_space(blocker, space)
		blockers[i] = blocker

		var rod: RID = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(rod, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(rod, rod_shape)
		PhysicsServer2D.body_set_param(rod, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_param(rod, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(rod, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(rod, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer2D.body_set_param(rod, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(rod, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_state(rod, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, origin))
		PhysicsServer2D.body_set_state(rod, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 5.0)
		PhysicsServer2D.body_set_continuous_collision_detection_mode(rod, PhysicsServer2D.CCD_MODE_CAST_RAY)
		PhysicsServer2D.body_set_space(rod, space)
		rods[i] = rod

	PhysicsServer2D.space_set_active(space, true)
	for i in range(5):
		await tree.physics_frame
	var intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var peak_pairs := 0
	var pair_sum := 0.0
	var peak_physics_ms := 0.0
	var finite := true
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		var pairs: int = int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
		peak_pairs = maxi(peak_pairs, pairs)
		pair_sum += float(pairs)
		peak_physics_ms = maxf(peak_physics_ms, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		for idx in [0, int(count / 2), count - 1]:
			var transform: Transform2D = PhysicsServer2D.body_get_state(rods[idx], PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(rods[idx], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 0.001:
				finite = false
		if not finite:
			break

	PhysicsServer2D.space_set_active(space, false)
	for rid in rods:
		PhysicsServer2D.free_rid(rid)
	for rid in blockers:
		PhysicsServer2D.free_rid(rid)
	PhysicsServer2D.free_rid(rod_shape)
	PhysicsServer2D.free_rid(blocker_shape)
	PhysicsServer2D.free_rid(space)
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	var result := {
		"dimension": 2, "tight": tight, "pairs_tested": count, "finite": finite,
		"peak_broadphase_pairs": peak_pairs, "mean_broadphase_pairs": pair_sum / maxf(1.0, float(intervals.size())),
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats, "frame_p95_ms": stats["p95"]
	}
	if not finite:
		result["error"] = "Rotating CCD rigid body developed unexpected linear motion"
	return result


func _run_3d(tree: SceneTree, scale: int, frames: int, tight: bool) -> Dictionary:
	const ROT_SETTING := "physics/3d/solver/ccd_rotational_bounds"
	const TIGHT_SETTING := "physics/3d/solver/ccd_tight_rotational_bounds"
	var old_rot: Variant = ProjectSettings.get_setting(ROT_SETTING, false)
	var old_tight: Variant = ProjectSettings.get_setting(TIGHT_SETTING, false)
	ProjectSettings.set_setting(ROT_SETTING, true)
	ProjectSettings.set_setting(TIGHT_SETTING, tight)
	var space: RID = PhysicsServer3D.space_create()
	ProjectSettings.set_setting(ROT_SETTING, old_rot)
	ProjectSettings.set_setting(TIGHT_SETTING, old_tight)

	var count := mini(64 * scale, 4096)
	var rod_shape: RID = PhysicsServer3D.box_shape_create()
	var blocker_shape: RID = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(rod_shape, Vector3(20.0, 0.2, 0.2))
	PhysicsServer3D.shape_set_data(blocker_shape, Vector3(0.2, 0.2, 0.2))
	var rods: Array[RID] = []
	var blockers: Array[RID] = []
	rods.resize(count)
	blockers.resize(count)
	for i in range(count):
		var origin := Vector3(float(i % 64) * 60.0, float(int(i / 64)) * 60.0, 0.0)
		var blocker: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(blocker, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(blocker, blocker_shape)
		PhysicsServer3D.body_set_state(blocker, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), origin + Vector3(10.45, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(blocker, space)
		blockers[i] = blocker

		var rod: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rod, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(rod, rod_shape)
		PhysicsServer3D.body_set_param(rod, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(rod, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rod, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rod, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.body_set_param(rod, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(rod, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(rod, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), origin))
		PhysicsServer3D.body_set_state(rod, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 0.0, 5.0))
		PhysicsServer3D.body_set_enable_continuous_collision_detection(rod, true)
		PhysicsServer3D.body_set_space(rod, space)
		rods[i] = rod

	PhysicsServer3D.space_set_active(space, true)
	for i in range(5):
		await tree.physics_frame
	var intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var peak_pairs := 0
	var pair_sum := 0.0
	var peak_physics_ms := 0.0
	var finite := true
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		var pairs: int = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
		peak_pairs = maxi(peak_pairs, pairs)
		pair_sum += float(pairs)
		peak_physics_ms = maxf(peak_physics_ms, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		for idx in [0, int(count / 2), count - 1]:
			var transform: Transform3D = PhysicsServer3D.body_get_state(rods[idx], PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(rods[idx], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 0.001:
				finite = false
		if not finite:
			break

	PhysicsServer3D.space_set_active(space, false)
	for rid in rods:
		PhysicsServer3D.free_rid(rid)
	for rid in blockers:
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.free_rid(rod_shape)
	PhysicsServer3D.free_rid(blocker_shape)
	PhysicsServer3D.free_rid(space)
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	var result := {
		"dimension": 3, "tight": tight, "pairs_tested": count, "finite": finite,
		"peak_broadphase_pairs": peak_pairs, "mean_broadphase_pairs": pair_sum / maxf(1.0, float(intervals.size())),
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": stats, "frame_p95_ms": stats["p95"]
	}
	if not finite:
		result["error"] = "Rotating CCD rigid body developed unexpected linear motion"
	return result
