# Identity vs rotated sphere-box narrowphase stress workload.
# Use tests/stress/run.py to compare frame time, peak RSS and pair throughput.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, rotated: bool) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var box_shape := PhysicsServer3D.box_shape_create()
	var sphere_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(box_shape, Vector3(2.0, 2.0, 2.0))
	PhysicsServer3D.shape_set_data(sphere_shape, 0.45)
	var basis := Basis(Vector3.UP, 0.37) if rotated else Basis()
	var count := mini(256 * scale, 4096)
	var boxes: Array[RID] = []
	var spheres: Array[RID] = []
	var initial_positions: Array[Vector3] = []
	boxes.resize(count)
	spheres.resize(count)
	initial_positions.resize(count)

	var create_start := Time.get_ticks_usec()
	for i in range(count):
		var origin := Vector3(float(i % 64) * 6.0, 0.0, float(int(i / 64)) * 6.0)
		var box := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(box, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(box, box_shape)
		PhysicsServer3D.body_set_state(box, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(basis, origin))
		PhysicsServer3D.body_set_space(box, space)
		boxes[i] = box

		var sphere := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(sphere, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(sphere, sphere_shape)
		PhysicsServer3D.body_set_param(sphere, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(sphere, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		var initial := origin + basis * Vector3(1.2, 0.0, 0.0)
		PhysicsServer3D.body_set_state(sphere, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), initial))
		PhysicsServer3D.body_set_space(sphere, space)
		spheres[i] = sphere
		initial_positions[i] = initial
	var creation_ms := float(Time.get_ticks_usec() - create_start) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var peak_pairs := 0
	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var transform_us := 0
	var last_tick := Time.get_ticks_usec()
	var error := ""
	for frame in range(frames):
		var update_start := Time.get_ticks_usec()
		for i in range(count):
			# Repeatedly drive the sphere back into contact so the benchmark
			# exercises narrowphase instead of only a settled cached manifold.
			var x := 0.02 if frame % 2 == 0 else -0.02
			var position := initial_positions[i] + basis * Vector3(x, 0.0, 0.0)
			PhysicsServer3D.body_set_state(spheres[i], PhysicsServer3D.BODY_STATE_TRANSFORM,
					Transform3D(Basis(), position))
		transform_us += Time.get_ticks_usec() - update_start
		await tree.physics_frame
		var tick := Time.get_ticks_usec()
		frame_intervals.append(float(tick - last_tick) / 1000.0)
		last_tick = tick
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for body in [spheres[0], spheres[int(count / 2)], spheres[count - 1]]:
			var transform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite():
				error = "Nonfinite sphere-box contact position or velocity"
				break
		if error != "":
			break

	PhysicsServer3D.space_set_active(space, false)
	for body in spheres:
		PhysicsServer3D.free_rid(body)
	for body in boxes:
		PhysicsServer3D.free_rid(body)
	spheres.clear()
	boxes.clear()
	initial_positions.clear()
	PhysicsServer3D.free_rid(sphere_shape)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(space)

	if error != "":
		return {"error": error}
	if peak_pairs == 0:
		return {"error": "No 3D sphere-box contacts were detected"}
	var stats: Dictionary = tree.call("_frame_statistics", frame_intervals)
	return {
		"sphere_box_pairs": count, "total_bodies": count * 2, "rotated_fallback": rotated,
		"physics_frames": frames, "creation_ms": creation_ms,
		"transform_update_ms": float(transform_us) / 1000.0,
		"peak_collision_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"],
	}
