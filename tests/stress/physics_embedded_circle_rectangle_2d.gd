# Compare the embedded-circle nearest-face fast path and existing outside path.
# Keep the same number of overlapping circle/rectangle pairs in both runs.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, embedded: bool) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var box_shape := PhysicsServer2D.rectangle_shape_create()
	var circle_shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(box_shape, Vector2(1.0, 1.0))
	PhysicsServer2D.shape_set_data(circle_shape, 0.35)
	var count := mini(256 * scale, 4096)
	var boxes: Array[RID] = []
	var circles: Array[RID] = []
	var initial_positions: Array[Vector2] = []
	boxes.resize(count)
	circles.resize(count)
	initial_positions.resize(count)
	var creation_start := Time.get_ticks_usec()
	var local_center := Vector2(0.75, 0.0) if embedded else Vector2(1.15, 0.0)
	for i in range(count):
		var origin := Vector2(float(i % 64) * 6.0, float(int(i / 64)) * 6.0)
		var box := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(box, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(box, box_shape)
		PhysicsServer2D.body_set_state(box, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, origin))
		PhysicsServer2D.body_set_space(box, space)
		boxes[i] = box

		var circle := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(circle, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(circle, circle_shape)
		PhysicsServer2D.body_set_param(circle, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(circle, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		var initial := origin + local_center
		PhysicsServer2D.body_set_state(circle, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, initial))
		PhysicsServer2D.body_set_space(circle, space)
		circles[i] = circle
		initial_positions[i] = initial
	var creation_ms := float(Time.get_ticks_usec() - creation_start) / 1000.0
	PhysicsServer2D.space_set_active(space, true)

	var intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	var update_us := 0
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var error := ""
	for frame in range(frames):
		var update_start := Time.get_ticks_usec()
		for i in range(count):
			# Refresh a real overlap each step: do not rely only on a settled
			# manifold cache when comparing the general and analytic path.
			var offset := Vector2(0.02 if frame % 2 == 0 else -0.02, 0.0)
			PhysicsServer2D.body_set_state(circles[i], PhysicsServer2D.BODY_STATE_TRANSFORM,
					Transform2D(0.0, initial_positions[i] + offset))
		update_us += Time.get_ticks_usec() - update_start
		await tree.physics_frame
		var tick := Time.get_ticks_usec()
		intervals.append(float(tick - last_tick) / 1000.0)
		last_tick = tick
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for circle in [circles[0], circles[int(count / 2)], circles[count - 1]]:
			var pose: Transform2D = PhysicsServer2D.body_get_state(circle, PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(circle, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite():
				error = "Non-finite embedded circle/rectangle physics state"
				break
		if error != "":
			break

	PhysicsServer2D.space_set_active(space, false)
	for circle in circles:
		PhysicsServer2D.free_rid(circle)
	for box in boxes:
		PhysicsServer2D.free_rid(box)
	PhysicsServer2D.free_rid(circle_shape)
	PhysicsServer2D.free_rid(box_shape)
	PhysicsServer2D.free_rid(space)
	if error != "":
		return {"error": error}
	if peak_pairs == 0:
		return {"error": "No embedded circle/rectangle collision pairs"}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"circle_rectangle_pairs": count, "total_bodies": count * 2,
		"embedded": embedded, "physics_frames": frames, "creation_ms": creation_ms,
		"transform_update_ms": float(update_us) / 1000.0,
		"peak_collision_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"],
	}
