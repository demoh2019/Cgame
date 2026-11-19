# Convex 16-gon face/face clipping pressure, with and without relative rotation.
# Benchmarks contact generation and clip-plane evaluation in GodotPhysics3D.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, rotated: bool) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var prism := PhysicsServer3D.convex_polygon_shape_create()
	var vertices := PackedVector3Array()
	var sides := 16
	for i in range(sides):
		var angle := TAU * float(i) / float(sides)
		var x := cos(angle) * 1.1
		var z := sin(angle) * 1.1
		vertices.append(Vector3(x, -0.5, z))
		vertices.append(Vector3(x, 0.5, z))
	PhysicsServer3D.shape_set_data(prism, vertices)

	var count := mini(256 * scale, 4096)
	var fixed_bodies: Array[RID] = []
	var moving_bodies: Array[RID] = []
	var positions: Array[Vector3] = []
	fixed_bodies.resize(count)
	moving_bodies.resize(count)
	positions.resize(count)
	var basis := Basis(Vector3.UP, 0.17) if rotated else Basis()

	var create_start := Time.get_ticks_usec()
	for i in range(count):
		var origin := Vector3(float(i % 64) * 5.0, 0.0, float(int(i / 64)) * 5.0)
		var ground := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(ground, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(ground, prism)
		PhysicsServer3D.body_set_state(ground, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), origin))
		PhysicsServer3D.body_set_space(ground, space)
		fixed_bodies[i] = ground

		var moving := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(moving, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(moving, prism)
		PhysicsServer3D.body_set_param(moving, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(moving, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		var pose := origin + Vector3(0.15, 0.75, 0.10)
		PhysicsServer3D.body_set_state(moving, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, pose))
		PhysicsServer3D.body_set_space(moving, space)
		moving_bodies[i] = moving
		positions[i] = pose
	var creation_ms := float(Time.get_ticks_usec() - create_start) / 1000.0
	PhysicsServer3D.space_set_active(space, true)

	var samples: Array[float] = []
	var last_frame := Time.get_ticks_usec()
	var update_us := 0
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var error := ""
	for frame in range(frames):
		var update_start := Time.get_ticks_usec()
		var motion := Vector3(0.0, 0.02 if frame % 2 == 0 else -0.02, 0.0)
		for i in range(count):
			PhysicsServer3D.body_set_state(moving_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM,
					Transform3D(basis, positions[i] + motion))
		update_us += Time.get_ticks_usec() - update_start
		await tree.physics_frame
		var tick := Time.get_ticks_usec()
		samples.append(float(tick - last_frame) / 1000.0)
		last_frame = tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for moving in [moving_bodies[0], moving_bodies[int(count / 2)], moving_bodies[count - 1]]:
			var pose: Transform3D = PhysicsServer3D.body_get_state(moving, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(moving, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite():
				error = "Non-finite 3D convex face manifold"
				break
		if error != "":
			break

	PhysicsServer3D.space_set_active(space, false)
	for moving in moving_bodies:
		PhysicsServer3D.free_rid(moving)
	for fixed in fixed_bodies:
		PhysicsServer3D.free_rid(fixed)
	PhysicsServer3D.free_rid(prism)
	PhysicsServer3D.free_rid(space)

	if error != "":
		return {"error": error}
	if peak_pairs == 0:
		return {"error": "No convex 3D face pairs reported by physics server"}
	var stats: Dictionary = tree.call("_frame_statistics", samples)
	return {
		"face_pair_count": count, "total_bodies": count * 2, "face_vertices": sides,
		"relative_rotation": rotated, "physics_frames": frames,
		"creation_ms": creation_ms, "transform_update_ms": float(update_us) / 1000.0,
		"peak_collision_pairs": peak_pairs, "peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"],
	}
