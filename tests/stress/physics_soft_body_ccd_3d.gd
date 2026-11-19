extends RefCounted
## Swept soft-body vertex/triangle regression. A disconnected triangular
## patch travels completely through a pinned face during ONE physics step.
## Its final position is farther than the discrete contact thickness.


func _trial(tree: SceneTree, scale: int, use_ccd: bool) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_ccd", use_ccd)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_thickness", 0.12)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_compliance", 0.000001)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex", 8)
	var space := PhysicsServer3D.space_create()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-3.0, -3.0, 0.0), Vector3(3.0, -3.0, 0.0),
		Vector3(0.0, 3.0, 0.0),
		Vector3(-0.3, -0.3, 0.45), Vector3(0.3, -0.3, 0.45),
		Vector3(0.0, 0.3, 0.45)
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
	# The three free particles have inverse mass ~6 at total mass 1.
	# A -12 kg*m/s impulse produces a travel of about -1.2 m/60 Hz,
	# passing the face from +0.45 to -0.75 within a single frame.
	for body in bodies:
		for j in range(3, 6):
			PhysicsServer3D.soft_body_apply_point_impulse(body, j, Vector3(0.0, 0.0, -12.0))
	var started := Time.get_ticks_usec()
	await tree.physics_frame
	var finite := true
	var pins_unchanged := true
	var min_z := INF
	var mean_z := 0.0
	for i in range(count):
		var body := bodies[i]
		var offset := Vector3(float(i) * 8.0, 0.0, 0.0)
		var original := [
			Vector3(-3.0, -3.0, 0.0),
			Vector3(3.0, -3.0, 0.0),
			Vector3(0.0, 3.0, 0.0)
		]
		for j in range(3):
			var fixed: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(body, j)
			pins_unchanged = pins_unchanged and fixed.distance_to(offset + original[j]) < 0.0001
			finite = finite and fixed.is_finite()
		for j in range(3, 6):
			var moving: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(body, j)
			finite = finite and moving.is_finite()
			min_z = minf(min_z, moving.z)
			mean_z += moving.z
	mean_z /= float(count * 3)
	var simulation_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return {"bodies": count, "ccd": use_ccd, "finite": finite,
		"pins_fixed": pins_unchanged, "min_z": min_z,
		"mean_z": mean_z, "simulation_ms": simulation_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var keys := [
		"physics/3d/solver/soft_body_self_collision_ccd",
		"physics/3d/solver/soft_body_self_collision_thickness",
		"physics/3d/solver/soft_body_self_collision_compliance",
		"physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex",
		"physics/3d/solver/soft_body_self_collision_edge_edge",
		"physics/3d/solver/soft_body_self_collision_friction",
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
	for i in range(4, keys.size()):
		ProjectSettings.set_setting(keys[i], 0.0)
	var discrete: Dictionary = await _trial(tree, scale, false)
	var continuous: Dictionary = await _trial(tree, scale, true)
	for i in range(keys.size()):
		ProjectSettings.set_setting(keys[i], previous[i])

	var verified := (
		discrete.finite and continuous.finite
		and discrete.pins_fixed and continuous.pins_fixed
		and discrete.mean_z < -0.2
		and continuous.min_z > 0.02
		and continuous.mean_z > discrete.mean_z + 0.5
	)
	if not verified:
		return {"error": "Soft-body swept CCD failed to stop one-step tunneling",
			"discrete": discrete, "continuous": continuous}
	return {"soft_body_ccd_verified": true,
		"discrete": discrete, "continuous": continuous}
