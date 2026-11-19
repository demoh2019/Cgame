extends RefCounted
## Two nonadjacent structural edges cross at their INTERIORS, but no
## vertex projects inside an opposing triangle. This is missed by
## vertex/face-only self collision, and should be separated by edge BVH.


func _trial(tree: SceneTree, scale: int, enable_edge_contacts: bool) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_thickness", 0.12)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_compliance", 0.000001)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex", 8)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_edge_edge", enable_edge_contacts)
	var space := PhysicsServer3D.space_create()

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.8, 2.0, 0.0),
		Vector3(0.0, -3.0, 0.02),
		Vector3(0.0, 3.0, 0.02),
		Vector3(-0.5, -3.0, 0.02)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

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
		for j in range(3):
			PhysicsServer3D.soft_body_pin_point(body, j, true)
		PhysicsServer3D.soft_body_set_transform(
				body, Transform3D(Basis(), Vector3(float(i) * 8.0, 0.0, 0.0)))
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)
	PhysicsServer3D.space_set_active(space, true)

	var started := Time.get_ticks_usec()
	for frame in range(8):
		await tree.physics_frame
	var distance_sum := 0.0
	var minimum_distance := INF
	var finite := true
	var pinned := true
	for i in range(count):
		var body := bodies[i]
		var points: Array[Vector3] = []
		for j in range(6):
			var p: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(body, j)
			points.append(p)
			finite = finite and p.is_finite()
		var origin := Vector3(float(i) * 8.0, 0.0, 0.0)
		pinned = pinned and points[0].distance_to(origin + Vector3(-1.0, 0.0, 0.0)) < 0.0001
		pinned = pinned and points[1].distance_to(origin + Vector3(1.0, 0.0, 0.0)) < 0.0001
		pinned = pinned and points[2].distance_to(origin + Vector3(0.8, 2.0, 0.0)) < 0.0001
		var edge_distance := Geometry3D.get_closest_points_between_segments(
				points[0], points[1], points[3], points[4])
		var d: float = (edge_distance[0] as Vector3).distance_to(edge_distance[1] as Vector3)
		minimum_distance = minf(minimum_distance, d)
		distance_sum += d
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return {"bodies": count, "edge_enabled": enable_edge_contacts,
		"finite": finite, "pins_fixed": pinned,
		"mean_edge_distance": distance_sum / float(count),
		"min_edge_distance": minimum_distance, "simulation_ms": elapsed_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var keys := [
		"physics/3d/solver/soft_body_self_collision_thickness",
		"physics/3d/solver/soft_body_self_collision_compliance",
		"physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex",
		"physics/3d/solver/soft_body_self_collision_edge_edge",
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
	for index in range(4, keys.size()):
		ProjectSettings.set_setting(keys[index], 0.0)
	var baseline: Dictionary = await _trial(tree, scale, false)
	var repelled: Dictionary = await _trial(tree, scale, true)
	for index in range(keys.size()):
		ProjectSettings.set_setting(keys[index], previous[index])

	var verified := (
		baseline.finite and repelled.finite
		and baseline.pins_fixed and repelled.pins_fixed
		and baseline.mean_edge_distance < 0.04
		and repelled.mean_edge_distance > baseline.mean_edge_distance + 0.04
		and repelled.min_edge_distance > 0.06
	)
	if not verified:
		return {"error": "Structural cloth edge/edge contact did not separate crossing folds",
			"baseline": baseline, "repelled": repelled}
	return {"edge_self_collision_verified": true,
		"baseline": baseline, "repelled": repelled}
