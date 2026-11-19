extends RefCounted
## Closed tetrahedral surface, three pinned vertices and one free apex.
## Tests volume conservation against a disabled baseline, and checks that
## an OPEN mesh never receives a fictitious global-volume constraint.


func _volume(points: Array[Vector3]) -> float:
	# Tetra with outward-facing windings and origin shifted to vertex zero.
	var faces := PackedInt32Array([0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3])
	var volume := 0.0
	var origin := points[0]
	for i in range(0, faces.size(), 3):
		var a := points[faces[i]] - origin
		var b := points[faces[i + 1]] - origin
		var c := points[faces[i + 2]] - origin
		volume += a.dot(b.cross(c)) / 6.0
	return absf(volume)


func _run_trial(tree: SceneTree, scale: int, p_compliance: float, p_closed: bool) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_xpbd_volume_compliance", p_compliance)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_xpbd_area_compliance", 0.0)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_xpbd_compliance", 0.0)
	var space := PhysicsServer3D.space_create()
	var mesh := ArrayMesh.new()
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 0.0, 2.0)
	])
	var face_indices := PackedInt32Array([0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3])
	if not p_closed:
		face_indices.resize(9)
	surface[Mesh.ARRAY_INDEX] = face_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)

	var count := 4 * mini(scale, 8)
	var bodies: Array[RID] = []
	for lane in range(count):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.0)
		PhysicsServer3D.soft_body_set_damping_coefficient(body, 0.0)
		PhysicsServer3D.soft_body_set_collision_layer(body, 0)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_pin_point(body, 0, true)
		PhysicsServer3D.soft_body_pin_point(body, 1, true)
		PhysicsServer3D.soft_body_pin_point(body, 2, true)
		var base := Vector3(float(lane) * 5.0, 0.0, 0.0)
		PhysicsServer3D.soft_body_set_transform(body, Transform3D(Basis(), base))
		# Attaching computes the REST volume before intentionally collapsing
		# the unpinned apex; the solver must recover the original volume.
		PhysicsServer3D.soft_body_set_space(body, space)
		PhysicsServer3D.soft_body_move_point(body, 3, base + Vector3(0.0, 0.0, 0.6))
		bodies.append(body)
	PhysicsServer3D.space_set_active(space, true)

	var started := Time.get_ticks_usec()
	for frame in range(10):
		await tree.physics_frame
	var mean_error := 0.0
	var max_error := 0.0
	var pins_fixed := true
	var finite := true
	var rest_volume := 4.0 / 3.0
	for lane in range(count):
		var body := bodies[lane]
		var positions: Array[Vector3] = []
		for vertex in range(4):
			var position := PhysicsServer3D.soft_body_get_point_global_position(body, vertex)
			positions.append(position)
			finite = finite and position.is_finite()
		var base := Vector3(float(lane) * 5.0, 0.0, 0.0)
		pins_fixed = pins_fixed and positions[0].distance_to(base) < 0.0001
		pins_fixed = pins_fixed and positions[1].distance_to(base + Vector3(2.0, 0.0, 0.0)) < 0.0001
		pins_fixed = pins_fixed and positions[2].distance_to(base + Vector3(0.0, 2.0, 0.0)) < 0.0001
		var current_volume := _volume(positions)
		var error := absf(current_volume - rest_volume)
		mean_error += error
		max_error = maxf(max_error, error)
	var duration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return {"closed": p_closed, "compliance": p_compliance, "bodies": count,
		"finite": finite, "pins_fixed": pins_fixed, "mean_volume_error": mean_error / float(count),
		"max_volume_error": max_error, "simulation_ms": duration_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var keys := [
		"physics/3d/solver/soft_body_xpbd_volume_compliance",
		"physics/3d/solver/soft_body_xpbd_area_compliance",
		"physics/3d/solver/soft_body_xpbd_compliance"
	]
	var previous := []
	for key in keys:
		previous.append(ProjectSettings.get_setting(key))
	var baseline: Dictionary = await _run_trial(tree, scale, 0.0, true)
	var preserved: Dictionary = await _run_trial(tree, scale, 0.00000001, true)
	var open_surface: Dictionary = await _run_trial(tree, scale, 0.00000001, false)
	for i in range(keys.size()):
		ProjectSettings.set_setting(keys[i], previous[i])

	var verified := (
		baseline.finite and preserved.finite and open_surface.finite and
		baseline.pins_fixed and preserved.pins_fixed and open_surface.pins_fixed and
		baseline.mean_volume_error > 0.5 and
		preserved.mean_volume_error < baseline.mean_volume_error * 0.15 and
		preserved.max_volume_error < 0.06 and
		open_surface.mean_volume_error > 0.5
	)
	if not verified:
		return {"error": "Closed-mesh XPBD volume preservation or open-mesh rejection failed",
			"baseline": baseline, "preserved": preserved, "open_surface": open_surface}
	return {"xpbd_volume_verified": true, "open_mesh_rejected": true,
		"baseline": baseline, "preserved": preserved,
		"open_surface": open_surface, "frames_per_trial": 10}
