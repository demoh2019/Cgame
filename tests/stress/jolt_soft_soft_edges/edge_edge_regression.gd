extends SceneTree
## Native regression for two *crossing* triangle edges. No vertex is near
## either opposing face, so vertex-vertex and vertex-face tests miss contact.
## The second identical pair has disabled collision masks as a control.
##
## godot --headless --path tests/stress/jolt_soft_soft_edges --script res://edge_edge_regression.gd

const PREFIX := "JOLT_SOFT_SOFT_EDGE_EDGE_RESULT:"
const FRAMES := 75


func _initialize() -> void:
	call_deferred("_run")


func _mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _triangle_pair(x: float) -> Array[ArrayMesh]:
	var horizontal := _mesh(PackedVector3Array([
		Vector3(x - 0.9, 2.0, 0.0),
		Vector3(x + 0.9, 2.0, 0.0),
		Vector3(x, 2.0, 1.3),
	]))
	var vertical := _mesh(PackedVector3Array([
		Vector3(x, 1.1, 0.0),
		Vector3(x, 2.9, 0.0),
		Vector3(x, 2.0, -1.3),
	]))
	return [horizontal, vertical]


func _body(space: RID, mesh: ArrayMesh, layer: int, mask: int) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.8)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
	PhysicsServer3D.soft_body_set_collision_layer(body, layer)
	PhysicsServer3D.soft_body_set_collision_mask(body, mask)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	# Pin only the third tip, never the two endpoints of the crossing edge.
	PhysicsServer3D.soft_body_pin_point(body, 2, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var root := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Backend must be Jolt Physics")
	for name in ["soft_body_soft_contacts", "soft_body_soft_vertex_face_contacts", "soft_body_soft_edge_edge_contacts"]:
		if not bool(ProjectSettings.get_setting(root + name, false)):
			errors.append("Missing required contact mode: " + name)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = []
	meshes.append_array(_triangle_pair(0.0))
	meshes.append_array(_triangle_pair(5.0))
	var bodies: Array[RID] = [
		_body(space, meshes[0], 1, 1),
		_body(space, meshes[1], 1, 1),
		_body(space, meshes[2], 2, 0),
		_body(space, meshes[3], 2, 0),
	]

	for frame in range(2):
		await physics_frame

	var started_usec := Time.get_ticks_usec()

	for frame in range(FRAMES):
		await physics_frame
		for i in range(4):
			var bounds := PhysicsServer3D.soft_body_get_bounds(bodies[i])
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				errors.append("Invalid AABB at frame " + str(frame) + ", body " + str(i))
				break
			for vertex in range(3):
				var position := PhysicsServer3D.soft_body_get_point_global_position(bodies[i], vertex)
				if not position.is_finite():
					errors.append("Nonfinite vertex at frame " + str(frame) + ", body " + str(i))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

	var end_allowed_a := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
	var end_allowed_b := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var end_masked_a := PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 0)
	var end_masked_b := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)

	# Include displacement during the warmup frames: the first impulse
	# can already separate the crossing edges before the samples above.
	# The starting edges are both on z = 0 in each independent pair.
	var allowed_z_gap := end_allowed_a.z - end_allowed_b.z
	var masked_z_gap := end_masked_a.z - end_masked_b.z
	if allowed_z_gap < masked_z_gap + 0.015:
		errors.append("Crossing deformable edges did not generate a separating response")
	if absf(masked_z_gap) > 0.03:
		errors.append("Disabled collision mask changed the control pair")

	for i in range(4):
		if not PhysicsServer3D.soft_body_is_point_pinned(bodies[i], 2):
			errors.append("Pinned third vertex released on body " + str(i))

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"allowed_z_gap": allowed_z_gap,
		"masked_z_gap": masked_z_gap,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt crossing soft-body edges collide with mask control")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
