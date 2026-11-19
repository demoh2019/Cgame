extends SceneTree
## Jolt native self collision: one soft body contains two separate, closely
## stacked triangles; only *internal* particle-face contacts can separate
## them. The control is a single connected quad, whose one-ring neighbors
## must not repel each other.
##
## godot --headless --path tests/stress/jolt_soft_self --script res://self_collision_regression.gd

const PREFIX := "JOLT_SOFT_SELF_RESULT:"
const FRAMES := 75


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


func _folded_sheet() -> ArrayMesh:
	# Same x/z triangle at y=2.0 and y=2.055; indices are disconnected.
	# There are no cross-sheet topology edges, so they must self-collide.
	return _mesh(PackedVector3Array([
		Vector3(-0.8, 2.055, -0.7),
		Vector3(0.8, 2.055, -0.7),
		Vector3(0.0, 2.055, 0.9),
		Vector3(-0.8, 2.0, -0.7),
		Vector3(0.8, 2.0, -0.7),
		Vector3(0.0, 2.0, 0.9),
	]), PackedInt32Array([0, 1, 2, 3, 5, 4]))


func _adjacent_control() -> ArrayMesh:
	# Both triangles share an edge, forming one flat connected quad.
	# Any collision among these vertices is topologically adjacent noise.
	return _mesh(PackedVector3Array([
		Vector3(4.0, 2.0, -0.7),
		Vector3(5.6, 2.0, -0.7),
		Vector3(4.0, 2.0, 0.9),
		Vector3(5.6, 2.0, 0.9),
	]), PackedInt32Array([0, 2, 1, 1, 2, 3]))


func _body(space: RID, mesh: ArrayMesh, pins: Array[int]) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.6)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
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
		errors.append("Jolt backend required")
	if not bool(ProjectSettings.get_setting(prefix + "soft_body_self_contacts", false)):
		errors.append("Self collision toggle not enabled")
	if bool(ProjectSettings.get_setting(prefix + "soft_body_soft_contacts", true)):
		errors.append("Inter-body soft-soft collision must be disabled in this fixture")
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [_folded_sheet(), _adjacent_control()]
	var bodies: Array[RID] = [
		_body(space, meshes[0], [0, 3]),
		_body(space, meshes[1], [0, 3]),
	]
	for i in range(2):
		await physics_frame
	var initial_top := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 1)
	var initial_bottom := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 4)
	var start_gap := initial_top.y - initial_bottom.y
	var control_start := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 1)
	var start := Time.get_ticks_usec()

	for frame in range(FRAMES):
		await physics_frame
		for body_idx in range(2):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[body_idx])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Nonfinite bounds at frame " + str(frame))
				break
			for vertex in range(6 if body_idx == 0 else 4):
				if not PhysicsServer3D.soft_body_get_point_global_position(bodies[body_idx], vertex).is_finite():
					errors.append("Nonfinite vertex at frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

	var final_top := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 1)
	var final_bottom := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 4)
	var end_gap := final_top.y - final_bottom.y
	var control_end := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 1)
	var control_drift := control_start.distance_to(control_end)
	if end_gap <= start_gap + 0.018:
		errors.append("Nonadjacent folded layers did not separate from self contacts")
	if control_drift > 0.035:
		errors.append("Adjacent faces repelled each other despite one-ring filter")
	for index in [0, 3]:
		if not PhysicsServer3D.soft_body_is_point_pinned(bodies[0], index):
			errors.append("Folded-sheet anchor lost at index " + str(index))
		if not PhysicsServer3D.soft_body_is_point_pinned(bodies[1], index):
			errors.append("Control-sheet anchor lost at index " + str(index))

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"start_gap": start_gap,
		"end_gap": end_gap,
		"adjacent_control_drift": control_drift,
		"elapsed_ms": float(Time.get_ticks_usec() - start) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt nonlocal soft self collision and one-ring suppression")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
