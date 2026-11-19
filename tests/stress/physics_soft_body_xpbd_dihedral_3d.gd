extends RefCounted
## Two triangle cloth hinge, with a pinned seam and one free vertex.
## Zero link/area/volume stiffness isolates XPBD dihedral bending.


func _hinge_angle(points: Array[Vector3]) -> float:
	var edge := points[1] - points[0]
	var nc := edge.cross(points[2] - points[0])
	var nd := (points[3] - points[0]).cross(edge)
	if edge.length_squared() < 0.00000001 or nc.length_squared() < 0.00000001 or nd.length_squared() < 0.00000001:
		return INF
	var axis := edge.normalized()
	var n1 := nc.normalized()
	var n2 := nd.normalized()
	return absf(atan2(axis.dot(n1.cross(n2)), n1.dot(n2)))


func _trial(tree: SceneTree, scale: int, compliance: float, wrong_winding: bool) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_xpbd_dihedral_compliance", compliance)
	# Disable all other optional positional constraints to isolate the hinge.
	var space := PhysicsServer3D.space_create()
	var mesh := ArrayMesh.new()
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, -1.0, 0.0)
	])
	# The second face must cross the shared edge 1 -> 0.
	surface[Mesh.ARRAY_INDEX] = PackedInt32Array(
		[0, 1, 2, 0, 1, 3] if wrong_winding else [0, 1, 2, 1, 0, 3])
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
		for index in [0, 1, 2]:
			PhysicsServer3D.soft_body_pin_point(body, index, true)
		var origin := Vector3(float(i) * 5.0, 0.0, 0.0)
		PhysicsServer3D.soft_body_set_transform(body, Transform3D(Basis(), origin))
		PhysicsServer3D.soft_body_set_space(body, space)
		# Deform AFTER rest dihedral capture; the solver should restore a
		# flat fold while keeping the three pinned particles in place.
		PhysicsServer3D.soft_body_move_point(body, 3, origin + Vector3(0.0, -1.0, 0.7))
		bodies.append(body)
	PhysicsServer3D.space_set_active(space, true)

	var started := Time.get_ticks_usec()
	var first_angle := 0.0
	var mean_angle := 0.0
	var max_angle := 0.0
	var finite := true
	var pins_fixed := true
	for frame in range(8):
		await tree.physics_frame
		if frame == 0:
			var initial_points: Array[Vector3] = []
			for index in range(4):
				initial_points.append(PhysicsServer3D.soft_body_get_point_global_position(bodies[0], index))
			first_angle = _hinge_angle(initial_points)
	for i in range(count):
		var body := bodies[i]
		var points: Array[Vector3] = []
		for index in range(4):
			var point: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(body, index)
			points.append(point)
			finite = finite and point.is_finite()
		var origin := Vector3(float(i) * 5.0, 0.0, 0.0)
		pins_fixed = pins_fixed and points[0].distance_to(origin + Vector3(-1.0, 0.0, 0.0)) < 0.0001
		pins_fixed = pins_fixed and points[1].distance_to(origin + Vector3(1.0, 0.0, 0.0)) < 0.0001
		pins_fixed = pins_fixed and points[2].distance_to(origin + Vector3(0.0, 1.0, 0.0)) < 0.0001
		var angle := _hinge_angle(points)
		finite = finite and is_finite(angle)
		mean_angle += angle
		max_angle = maxf(max_angle, angle)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)

	return {"soft_bodies": count, "wrong_winding": wrong_winding,
		"compliance": compliance, "finite": finite, "pins_fixed": pins_fixed,
		"first_angle": first_angle, "mean_angle": mean_angle / float(count),
		"max_angle": max_angle, "simulation_ms": elapsed_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var keys := [
		"physics/3d/solver/soft_body_xpbd_dihedral_compliance",
		"physics/3d/solver/soft_body_xpbd_compliance",
		"physics/3d/solver/soft_body_xpbd_area_compliance",
		"physics/3d/solver/soft_body_xpbd_volume_compliance",
		"physics/3d/solver/soft_body_xpbd_tether_compliance"
	]
	var previous: Array = []
	for key in keys:
		previous.append(ProjectSettings.get_setting(key))
	for i in range(1, keys.size()):
		ProjectSettings.set_setting(keys[i], 0.0)

	var baseline: Dictionary = await _trial(tree, scale, 0.0, false)
	var bent: Dictionary = await _trial(tree, scale, 0.000001, false)
	var malformed: Dictionary = await _trial(tree, scale, 0.000001, true)
	for i in range(keys.size()):
		ProjectSettings.set_setting(keys[i], previous[i])
	var correct := (
		baseline.finite and bent.finite and malformed.finite
		and baseline.pins_fixed and bent.pins_fixed and malformed.pins_fixed
		and baseline.mean_angle > 0.4
		and bent.mean_angle < baseline.mean_angle * 0.25
		and bent.max_angle < 0.2
		and malformed.mean_angle > 0.4
	)
	if not correct:
		return {"error": "XPBD dihedral cloth bend, pins or winding filter failed",
			"baseline": baseline, "bent": bent, "malformed": malformed}
	return {"dihedral_bending_verified": true, "malformed_winding_rejected": true,
		"baseline": baseline, "bent": bent, "malformed": malformed}
