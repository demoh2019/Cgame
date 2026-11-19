extends RefCounted
## End-to-end cloth surface-area preservation with two pinned vertices.
## Stretch stiffness is zero to isolate the new area constraint, so gravity
## would collapse the free vertex onto the base without XPBD area correction.


func _run_trial(tree: SceneTree, scale: int, p_area_compliance: float) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_xpbd_area_compliance", p_area_compliance)
	ProjectSettings.set_setting("physics/3d/solver/soft_body_xpbd_compliance", 0.0)
	# Each new GodotSpace3D snapshots its solver settings at creation.
	var space := PhysicsServer3D.space_create()
	var mesh := ArrayMesh.new()
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0),
		Vector3(1.0, 2.0, 0.0)
	])
	surface[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)

	var count := 4 * mini(scale, 8)
	var bodies: Array[RID] = []
	for i in range(count):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.0)
		PhysicsServer3D.soft_body_set_damping_coefficient(body, 0.0)
		PhysicsServer3D.soft_body_pin_point(body, 0, true)
		PhysicsServer3D.soft_body_pin_point(body, 1, true)
		PhysicsServer3D.soft_body_set_collision_layer(body, 0)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_transform(body, Transform3D(Basis(), Vector3(float(i) * 4.0, 0.0, 0.0)))
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)

	PhysicsServer3D.space_set_active(space, true)
	var started := Time.get_ticks_usec()
	for i in range(24):
		await tree.physics_frame

	var max_error := 0.0
	var mean_error := 0.0
	var finite := true
	var pins_unchanged := true
	for body in bodies:
		var p0 := PhysicsServer3D.soft_body_get_point_global_position(body, 0)
		var p1 := PhysicsServer3D.soft_body_get_point_global_position(body, 1)
		var p2 := PhysicsServer3D.soft_body_get_point_global_position(body, 2)
		finite = finite and p0.is_finite() and p1.is_finite() and p2.is_finite()
		var area := (p1 - p0).cross(p2 - p0).length() * 0.5
		var error := absf(area - 2.0)
		max_error = maxf(max_error, error)
		mean_error += error
		pins_unchanged = pins_unchanged and absf(p0.y) < 0.0001 and absf(p1.y) < 0.0001
	var duration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return {"soft_bodies": count, "finite": finite, "pins_unchanged": pins_unchanged,
		"max_area_error": max_error, "mean_area_error": mean_error / float(count),
		"duration_ms": duration_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var area_key := "physics/3d/solver/soft_body_xpbd_area_compliance"
	var distance_key := "physics/3d/solver/soft_body_xpbd_compliance"
	var previous_area = ProjectSettings.get_setting(area_key)
	var previous_distance = ProjectSettings.get_setting(distance_key)
	var baseline: Dictionary = await _run_trial(tree, scale, 0.0)
	var preserved: Dictionary = await _run_trial(tree, scale, 0.000001)
	ProjectSettings.set_setting(area_key, previous_area)
	ProjectSettings.set_setting(distance_key, previous_distance)

	# Both runs use the same open triangle, pinned base and zero edge
	# stiffness. Only the optional XPBD area constraint can support the
	# free vertex against gravity. This compares the actual solver output.
	var valid := (
		baseline.finite and preserved.finite and
		baseline.pins_unchanged and preserved.pins_unchanged and
		baseline.mean_area_error > 0.1 and
		preserved.mean_area_error < baseline.mean_area_error * 0.5 and
		preserved.max_area_error < 0.15
	)
	if not valid:
		return {"error": "XPBD cloth area constraint failed to preserve triangle area",
			"baseline": baseline, "area_xpbd": preserved}
	return {"area_preservation_verified": true, "baseline": baseline,
		"area_xpbd": preserved, "frames_per_trial": 24}
