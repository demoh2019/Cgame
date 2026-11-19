# Box/capsule and box/cylinder contact SAT; compare near and far world origins.
# Each workload repositions all dynamic bodies each frame to stress narrowphase.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, capsule: bool, far_origin: bool) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var box_shape := PhysicsServer3D.box_shape_create()
	var rounded_shape := PhysicsServer3D.capsule_shape_create() if capsule else PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(box_shape, Vector3(2.0, 2.0, 2.0))
	PhysicsServer3D.shape_set_data(rounded_shape, {"radius": 0.4, "height": 2.0})
	var count := mini(256 * scale, 4096)
	var boxes: Array[RID] = []
	var bodies: Array[RID] = []
	var starting_poses: Array[Transform3D] = []
	boxes.resize(count)
	bodies.resize(count)
	starting_poses.resize(count)
	var base_origin := Vector3(8192.0, -4096.0, 12288.0) if far_origin else Vector3.ZERO

	var creation_start := Time.get_ticks_usec()
	for i in range(count):
		var offset := Vector3(float(i % 64) * 6.0, 0.0, float(int(i / 64)) * 6.0)
		var origin := base_origin + offset
		var box := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(box, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(box, box_shape)
		PhysicsServer3D.body_set_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), origin))
		PhysicsServer3D.body_set_space(box, space)
		boxes[i] = box

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, rounded_shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		var pose := Transform3D(Basis(), origin + Vector3(1.2, 0.0, 0.2))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
		starting_poses[i] = pose

	var creation_ms := float(Time.get_ticks_usec() - creation_start) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var intervals: Array[float] = []
	var transform_us := 0
	var last_tick := Time.get_ticks_usec()
	var error := ""
	for frame in range(frames):
		var update_start := Time.get_ticks_usec()
		for i in range(count):
			var pose: Transform3D = starting_poses[i]
			pose.origin.x += 0.03 if frame % 2 == 0 else -0.03
			PhysicsServer3D.body_set_state(bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
		transform_us += Time.get_ticks_usec() - update_start
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [bodies[0], bodies[int(count / 2)], bodies[count - 1]]:
			var transform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite():
				error = "Non-finite box/rounded-shape SAT state"
				break
		if error != "":
			break

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for box in boxes:
		PhysicsServer3D.free_rid(box)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(rounded_shape)
	PhysicsServer3D.free_rid(space)

	if error != "":
		return {"error": error}
	if peak_pairs == 0:
		return {"error": "No box/capsule or box/cylinder pairs registered"}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"pair_shape": "capsule" if capsule else "cylinder",
		"far_origin": far_origin, "total_bodies": count * 2,
		"box_pairs": count, "physics_frames": frames,
		"creation_ms": creation_ms, "transform_update_ms": float(transform_us) / 1000.0,
		"peak_collision_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"],
	}
