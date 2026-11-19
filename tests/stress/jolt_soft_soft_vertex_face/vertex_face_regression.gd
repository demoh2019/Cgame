extends SceneTree
## Native regression: one tetrahedron vertex over the interior of a large
## triangle. No triangle vertex is near the tetrahedron tip, so the legacy
## vertex-vertex contact algorithm cannot detect this pair.
## A duplicated pair with collision masks disabled is the control.
## --headless --path tests/stress/jolt_soft_soft_vertex_face --script res://vertex_face_regression.gd

const PREFIX := "JOLT_SOFT_SOFT_VERTEX_FACE_RESULT:"
const FRAMES := 50


func _initialize() -> void:
	call_deferred("_run")


func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _plane_mesh(x: float) -> ArrayMesh:
	return _mesh(PackedVector3Array([
		Vector3(x - 1.0, 2.0, -1.0),
		Vector3(x + 1.0, 2.0, -1.0),
		Vector3(x, 2.0, 1.0),
	]), PackedInt32Array([0, 2, 1]))


func _tetra_mesh(x: float) -> ArrayMesh:
	return _mesh(PackedVector3Array([
		Vector3(x, 2.045, 0),
		Vector3(x + 0.2, 2.45, 0),
		Vector3(x - 0.2, 2.45, 0),
		Vector3(x, 2.45, 0.22),
	]), PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	]))


func _body(space: RID, mesh: ArrayMesh, layer: int, mask: int, plane: bool) -> RID:
	var rid := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(rid, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(rid, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(rid, 0.6)
	PhysicsServer3D.soft_body_set_simulation_precision(rid, 8)
	PhysicsServer3D.soft_body_set_collision_layer(rid, layer)
	PhysicsServer3D.soft_body_set_collision_mask(rid, mask)
	PhysicsServer3D.soft_body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	if plane:
		# Two pinned, one dynamic vertex: keeps the soft body active while
		# retaining a deformable triangle with nonzero effective face mass.
		PhysicsServer3D.soft_body_pin_point(rid, 0, true)
		PhysicsServer3D.soft_body_pin_point(rid, 1, true)
	PhysicsServer3D.soft_body_set_space(rid, space)
	return rid


func _run() -> void:
	var errors: Array[String] = []
	var root := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Wrong physics engine")
	for key in ["soft_body_soft_contacts", "soft_body_soft_vertex_face_contacts"]:
		if not bool(ProjectSettings.get_setting(root + key, false)):
			errors.append("Feature disabled: " + key)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)

	# Keep all mesh resources alive throughout the test.
	var meshes: Array[ArrayMesh] = [
		_plane_mesh(0.0), _tetra_mesh(0.0),
		_plane_mesh(6.0), _tetra_mesh(6.0),
	]
	var bodies: Array[RID] = [
		_body(space, meshes[0], 1, 1, true),
		_body(space, meshes[1], 1, 1, false),
		_body(space, meshes[2], 2, 0, true),
		_body(space, meshes[3], 2, 0, false),
	]

	for i in range(2):
		await physics_frame

	var initial_allowed := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var initial_masked := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	var start_usec := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame
		for i in range(bodies.size()):
			var bounds := PhysicsServer3D.soft_body_get_bounds(bodies[i])
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				errors.append("Nonfinite bounds for body " + str(i) + " frame " + str(frame))
				break
			for vertex in range(3 if i % 2 == 0 else 4):
				var position := PhysicsServer3D.soft_body_get_point_global_position(bodies[i], vertex)
				if not position.is_finite():
					errors.append("Nonfinite vertex in body " + str(i) + " frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break
	var final_allowed := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var final_masked := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	var allowed_lift := final_allowed.y - initial_allowed.y
	var masked_lift := final_masked.y - initial_masked.y
	if allowed_lift < masked_lift + 0.02:
		errors.append("Vertex-face contact did not lift the penetrating tetrahedron tip")
	if absf(masked_lift) > 0.03:
		errors.append("Masked control body moved unexpectedly")
	for plane_idx in [0, 2]:
		for pinned_idx in [0, 1]:
			if not PhysicsServer3D.soft_body_is_point_pinned(bodies[plane_idx], pinned_idx):
				errors.append("Pinned triangle vertex lost")

	for rid in bodies:
		PhysicsServer3D.soft_body_set_space(rid, RID())
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"allowed_lift": allowed_lift,
		"masked_lift": masked_lift,
		"errors": errors,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
	}))
	if errors.is_empty():
		print("PASS: Jolt sparse soft-soft vertex-face contacts and masked control")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
