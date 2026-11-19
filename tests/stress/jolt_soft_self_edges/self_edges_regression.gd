extends SceneTree
## Native Jolt soft-body self edge/edge contact regression.
## One soft body contains two disconnected crossing triangles; no vertex
## intersects the other triangle, so legacy self vertex-face cannot catch
## the crossing. A second body is a connected quad (one-ring control).
## Run: --headless --path tests/stress/jolt_soft_self_edges --script res://self_edges_regression.gd

const PREFIX := "JOLT_SOFT_SELF_EDGES_RESULT:"
const FRAMES := 75


func _initialize() -> void:
	call_deferred("_run")


func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _crossed_unconnected_triangles() -> ArrayMesh:
	# First edge lies along X; second edge lies along Y. The edges cross
	# in their interiors at (0, 2, 0), but all endpoints are far apart.
	return _mesh(PackedVector3Array([
		Vector3(-0.9, 2.0, 0.0),
		Vector3(0.9, 2.0, 0.0),
		Vector3(0.0, 2.0, 1.3),
		Vector3(0.0, 1.1, 0.0),
		Vector3(0.0, 2.9, 0.0),
		Vector3(0.0, 2.0, -1.3),
	]), PackedInt32Array([0, 1, 2, 3, 4, 5]))


func _connected_quad_control() -> ArrayMesh:
	# Every edge pair in this quad is adjacent or one-ring connected.
	# Enabling self EE must not introduce artificial internal repulsion.
	return _mesh(PackedVector3Array([
		Vector3(4.0, 2.0, -0.8),
		Vector3(5.5, 2.0, -0.8),
		Vector3(4.0, 2.0, 0.8),
		Vector3(5.5, 2.0, 0.8),
	]), PackedInt32Array([0, 2, 1, 1, 2, 3]))


func _body(space: RID, mesh: ArrayMesh, pins: Array[int]) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.8)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
	PhysicsServer3D.soft_body_set_collision_layer(body, 0)
	PhysicsServer3D.soft_body_set_collision_mask(body, 0)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	for index in pins:
		PhysicsServer3D.soft_body_pin_point(body, index, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var base := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Expected Jolt Physics backend")
	for key in ["soft_body_self_contacts", "soft_body_self_edge_contacts"]:
		if not bool(ProjectSettings.get_setting(base + key, false)):
			errors.append("Missing feature: " + key)
	if bool(ProjectSettings.get_setting(base + "soft_body_soft_contacts", true)):
		errors.append("Cross-body collision must be disabled for isolation")
	if not errors.is_empty():
		for message in errors:
			printerr(message)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [_crossed_unconnected_triangles(), _connected_quad_control()]
	var bodies: Array[RID] = [
		_body(space, meshes[0], [2, 5]),
		_body(space, meshes[1], [0, 3]),
	]
	var max_separation := 0.0
	var max_control_drift := 0.0
	var control_reference := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 1)
	var started := Time.get_ticks_usec()

	for frame in range(FRAMES):
		await physics_frame
		for body_idx in range(2):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[body_idx])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Invalid bounds in frame " + str(frame))
				break
			for vertex in range(6 if body_idx == 0 else 4):
				var position := PhysicsServer3D.soft_body_get_point_global_position(bodies[body_idx], vertex)
				if not position.is_finite():
					errors.append("Nonfinite vertex at frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

		var edge_a := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
		var edge_b := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 3)
		max_separation = maxf(max_separation, absf(edge_a.z - edge_b.z))
		var control_now := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 1)
		max_control_drift = maxf(max_control_drift, control_now.distance_to(control_reference))

	if max_separation < 0.025:
		errors.append("Crossing nonadjacent edges inside one soft body did not separate")
	if max_control_drift > 0.04:
		errors.append("Connected quad developed false adjacency self-edge impulses")
	for index in [2, 5]:
		if not PhysicsServer3D.soft_body_is_point_pinned(bodies[0], index):
			errors.append("Crossing triangle pinned tip released: " + str(index))
	for index in [0, 3]:
		if not PhysicsServer3D.soft_body_is_point_pinned(bodies[1], index):
			errors.append("Control quad pinned point released: " + str(index))

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"max_edge_separation_z": max_separation,
		"max_adjacent_control_drift": max_control_drift,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt self edge-edge contacts suppress one-ring adjacency")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
