extends SceneTree
## Headless regression for opt-in Jacobi self-contact projection.
## Velocity recovery and gravity are OFF: only the positional solver should
## separate nonadjacent folded faces and crossing edges. A connected quad is
## a topology-control object; all cross-body masks are disabled.
## Run: --headless --path tests/stress/jolt_soft_self_position --script res://position_projection_regression.gd

const PREFIX := "JOLT_SELF_POSITION_RESULT:"
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


func _folded_faces() -> ArrayMesh:
	return _mesh(PackedVector3Array([
		Vector3(-0.8, 2.055, -0.7),
		Vector3(0.8, 2.055, -0.7),
		Vector3(0.0, 2.055, 0.9),
		Vector3(-0.8, 2.0, -0.7),
		Vector3(0.8, 2.0, -0.7),
		Vector3(0.0, 2.0, 0.9),
	]), PackedInt32Array([0, 1, 2, 3, 5, 4]))


func _crossed_edges() -> ArrayMesh:
	return _mesh(PackedVector3Array([
		Vector3(3.1, 2.0, 0.0),
		Vector3(4.9, 2.0, 0.0),
		Vector3(4.0, 2.0, 1.3),
		Vector3(4.0, 1.1, 0.0),
		Vector3(4.0, 2.9, 0.0),
		Vector3(4.0, 2.0, -1.3),
	]), PackedInt32Array([0, 1, 2, 3, 4, 5]))


func _adjacent_control() -> ArrayMesh:
	return _mesh(PackedVector3Array([
		Vector3(8.0, 2.0, -0.7),
		Vector3(9.6, 2.0, -0.7),
		Vector3(8.0, 2.0, 0.9),
		Vector3(9.6, 2.0, 0.9),
	]), PackedInt32Array([0, 2, 1, 1, 2, 3]))


func _body(space: RID, mesh: ArrayMesh, pins: Array[int]) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.7)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
	PhysicsServer3D.soft_body_set_collision_layer(body, 0)
	PhysicsServer3D.soft_body_set_collision_mask(body, 0)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	for vertex in pins:
		PhysicsServer3D.soft_body_pin_point(body, vertex, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var prefix := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("The Jolt backend is required")
	for setting in ["soft_body_self_contacts", "soft_body_self_edge_contacts", "soft_body_self_position_projection"]:
		if not bool(ProjectSettings.get_setting(prefix + setting, false)):
			errors.append("Missing physics setting: " + setting)
	if float(ProjectSettings.get_setting(prefix + "soft_body_soft_contact_recovery", -1.0)) != 0.0:
		errors.append("Velocity recovery must be zero to isolate the position projection")
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [_folded_faces(), _crossed_edges(), _adjacent_control()]
	var bodies: Array[RID] = [
		_body(space, meshes[0], [0, 3]),
		_body(space, meshes[1], [2, 5]),
		_body(space, meshes[2], [0, 3])
	]
	# Make sure the Jolt bodies have been inserted and soft particles
	# initialized before sampling the flat control's resting position.
	for warmup in range(2):
		await physics_frame
	var initial_fold_gap := 0.055
	var start_usec := Time.get_ticks_usec()
	var maximum_control_drift := 0.0
	var control_position := PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 1)

	for frame in range(FRAMES):
		await physics_frame
		for body_idx in range(3):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[body_idx])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Invalid AABB on frame " + str(frame))
				break
			for point_index in range(4 if body_idx == 2 else 6):
				var point := PhysicsServer3D.soft_body_get_point_global_position(bodies[body_idx], point_index)
				if not point.is_finite():
					errors.append("Invalid particle position on frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break
		maximum_control_drift = maxf(maximum_control_drift,
				control_position.distance_to(PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 1)))

	var fold_upper := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 1)
	var fold_lower := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 4)
	var folded_gap := fold_upper.y - fold_lower.y
	var edge_a := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var edge_b := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 3)
	var crossed_edge_separation := absf(edge_a.z - edge_b.z)
	if folded_gap < initial_fold_gap + 0.012:
		errors.append("Nonadjacent face layers failed to separate with velocity bias disabled")
	if crossed_edge_separation < 0.012:
		errors.append("Crossing edges failed to separate with velocity bias disabled")
	if maximum_control_drift > 0.05:
		errors.append("Topology-connected quad moved unexpectedly")

	for body_idx in range(3):
		var pins: Array[int] = [0, 3]
		if body_idx == 1:
			pins = [2, 5]
		for index in pins:
			if not PhysicsServer3D.soft_body_is_point_pinned(bodies[body_idx], index):
				errors.append("Pinned particle released, body " + str(body_idx))

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"folded_gap": folded_gap,
		"crossed_edge_separation": crossed_edge_separation,
		"control_max_drift": maximum_control_drift,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt compliant Jacobi self-contact position projection")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
