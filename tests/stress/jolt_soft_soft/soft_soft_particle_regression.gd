extends SceneTree
## Experimental CPU soft-soft *particle* contacts, not triangle/CCD contacts.
## A/B may collide, C/D deliberately have mutually disabled collision masks.
## godot --headless --path tests/stress/jolt_soft_soft --script res://soft_soft_particle_regression.gd

const PREFIX := "JOLT_SOFT_SOFT_RESULT:"
const FRAMES := 55


func _initialize() -> void:
	call_deferred("_run")


func _tetra_mesh(x_offset: float) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(x_offset, 3, 0),
		Vector3(x_offset + 0.5, 3, 0),
		Vector3(x_offset, 3.5, 0),
		Vector3(x_offset, 3, 0.5),
	])
	var indices := PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_body(space: RID, mesh: ArrayMesh, layer: int, mask: int, pin_start: bool) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.5)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
	PhysicsServer3D.soft_body_set_collision_layer(body, layer)
	PhysicsServer3D.soft_body_set_collision_mask(body, mask)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	if pin_start:
		PhysicsServer3D.soft_body_pin_point(body, 0, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var prefix := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Expected Jolt Physics")
	if not bool(ProjectSettings.get_setting(prefix + "soft_body_soft_contacts", false)):
		errors.append("CPU soft-soft collisions not enabled")
	if absf(float(ProjectSettings.get_setting(prefix + "soft_body_soft_contact_radius", 0.0)) - 0.16) > 0.0001:
		errors.append("Wrong contact radius")
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	# Retain mesh resources for the whole simulation.
	var meshes: Array[ArrayMesh] = [
		_tetra_mesh(0.0),
		_tetra_mesh(0.04),
		_tetra_mesh(5.0),
		_tetra_mesh(5.04)
	]
	var bodies: Array[RID] = [
		_make_body(space, meshes[0], 1, 1, true),
		_make_body(space, meshes[1], 1, 1, false),
		_make_body(space, meshes[2], 2, 0, false),
		_make_body(space, meshes[3], 2, 0, false)
	]

	for frame in range(2):
		await physics_frame
	var pinned_start := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
	var contact_initial := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 1).distance_to(PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 1))
	var masked_initial := PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 1).distance_to(PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 1))
	var started := Time.get_ticks_usec()

	for frame in range(FRAMES):
		await physics_frame
		for body_idx in range(bodies.size()):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[body_idx])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Invalid AABB in body " + str(body_idx) + ", frame " + str(frame))
				break
			for vertex_idx in range(4):
				if not PhysicsServer3D.soft_body_get_point_global_position(bodies[body_idx], vertex_idx).is_finite():
					errors.append("Nonfinite vertex in body " + str(body_idx) + ", frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break
		if PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0).distance_to(pinned_start) > 0.001:
			errors.append("Pinned particle drifted")
			break

	var contact_end := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 1).distance_to(PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 1))
	var masked_end := PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 1).distance_to(PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 1))
	if contact_end < masked_end + 0.015:
		errors.append("Allowed soft-soft pair did not separate relative to masked pair")
	if absf(masked_end - masked_initial) > 0.1:
		errors.append("Collision mask did not suppress soft-soft contact impulses")
	if not PhysicsServer3D.soft_body_is_point_pinned(bodies[0], 0):
		errors.append("Pinned particle lost its fixed mass")

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"contact_initial": contact_initial,
		"contact_final": contact_end,
		"masked_initial": masked_initial,
		"masked_final": masked_end,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt bounded soft-soft particle contact response and layer masks")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
