extends RefCounted
## Opt-in BVH vertex/face soft-body self collision.
## Two disconnected mesh layers start within the thickness envelope.
## A connected two-triangle mesh with a nearby vertex must be excluded
## by the structural one-ring adjacency filter.


func _trial(tree: SceneTree, scale: int, thickness: float, connected: bool) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_thickness", thickness)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_compliance", 0.000001)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex", 8)
	var space := PhysicsServer3D.space_create()
	var mesh := ArrayMesh.new()
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array([
		Vector3(-2.0, -2.0, 0.0), Vector3(2.0, -2.0, 0.0),
		Vector3(0.0, 2.0, 0.0)
	])
	if connected:
		verts.append(Vector3(0.0, 0.0, 0.02))
		surface[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 0, 3])
	else:
		verts.append(Vector3(-0.3, -0.3, 0.02))
		verts.append(Vector3(0.3, -0.3, 0.02))
		verts.append(Vector3(0.0, 0.2, 0.02))
		surface[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	surface[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)

	var count := 4 * mini(scale, 8)
	var bodies: Array[RID] = []
	for i in range(count):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.0)
		PhysicsServer3D.soft_body_set_damping_coefficient(body, 0.0)
		PhysicsServer3D.soft_body_set_collision_layer(body, 0)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		for base_vertex in range(3):
			PhysicsServer3D.soft_body_pin_point(body, base_vertex, true)
		PhysicsServer3D.soft_body_set_transform(body,
				Transform3D(Basis(), Vector3(float(i) * 6.0, 0.0, 0.0)))
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)

	PhysicsServer3D.space_set_active(space, true)
	var started := Time.get_ticks_usec()
	for step in range(8):
		await tree.physics_frame
	var mean_z := 0.0
	var min_z := INF
	var finite := true
	var pins_unchanged := true
	for i in range(count):
		var body := bodies[i]
		var origin := Vector3(float(i) * 6.0, 0.0, 0.0)
		for j in range(3):
			var expected := origin + verts[j]
			var point := PhysicsServer3D.soft_body_get_point_global_position(body, j)
			pins_unchanged = pins_unchanged and point.distance_to(expected) < 0.0001
			finite = finite and point.is_finite()
		for j in range(3, verts.size()):
			var point := PhysicsServer3D.soft_body_get_point_global_position(body, j)
			finite = finite and point.is_finite()
			mean_z += point.z
			min_z = minf(min_z, point.z)
	mean_z /= float(count * (verts.size() - 3))
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return {"bodies": count, "connected": connected, "thickness": thickness,
		"finite": finite, "pins_unchanged": pins_unchanged,
		"mean_z": mean_z, "minimum_z": min_z, "simulation_ms": elapsed_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var keys := [
		"physics/3d/solver/soft_body_self_collision_thickness",
		"physics/3d/solver/soft_body_self_collision_compliance",
		"physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex",
		"physics/3d/solver/soft_body_xpbd_compliance",
		"physics/3d/solver/soft_body_xpbd_area_compliance",
		"physics/3d/solver/soft_body_xpbd_dihedral_compliance",
		"physics/3d/solver/soft_body_xpbd_volume_compliance",
		"physics/3d/solver/soft_body_xpbd_tether_compliance",
		"physics/3d/solver/soft_body_plastic_creep_rate"
	]
	var previous := []
	for key in keys:
		previous.append(ProjectSettings.get_setting(key))
	for index in range(3, keys.size()):
		ProjectSettings.set_setting(keys[index], 0.0)

	var baseline: Dictionary = await _trial(tree, scale, 0.0, false)
	var repelled: Dictionary = await _trial(tree, scale, 0.12, false)
	var adjacent: Dictionary = await _trial(tree, scale, 0.12, true)
	for index in range(keys.size()):
		ProjectSettings.set_setting(keys[index], previous[index])

	var correct := (
		baseline.finite and repelled.finite and adjacent.finite and
		baseline.pins_unchanged and repelled.pins_unchanged and adjacent.pins_unchanged and
		baseline.mean_z < 0.04 and
		repelled.mean_z > baseline.mean_z + 0.04 and
		repelled.minimum_z > 0.07 and
		adjacent.mean_z < 0.04
	)
	if not correct:
		return {"error": "BVH soft-body self contact failed layer separation or adjacency",
			"baseline": baseline, "repelled": repelled, "adjacent": adjacent}
	return {"self_collision_verified": true, "one_ring_excluded": true,
		"baseline": baseline, "repelled": repelled, "adjacent": adjacent}
