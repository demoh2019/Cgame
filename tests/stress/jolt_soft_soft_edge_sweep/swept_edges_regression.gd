extends SceneTree
## Native Jolt regression: a fast, deformable horizontal triangle edge
## advances through a stationary vertical triangle edge within one fixed
## time step. No vertex is close enough for a vertex-face contact. A second
## identical pair with mutually disabled masks is the control.
## Run: --headless --path tests/stress/jolt_soft_soft_edge_sweep --script res://swept_edges_regression.gd

const PREFIX := "JOLT_SOFT_SWEPT_EDGES_RESULT:"
const FRAMES := 4


func _initialize() -> void:
	call_deferred("_run")


func _triangle(points: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _pair_meshes(offset_x: float) -> Array[ArrayMesh]:
	var moving := _triangle(PackedVector3Array([
		Vector3(offset_x - 0.9, 2.0, -0.38),
		Vector3(offset_x + 0.9, 2.0, -0.38),
		Vector3(offset_x, 2.0, -1.3),
	]))
	var target := _triangle(PackedVector3Array([
		Vector3(offset_x, 1.1, 0.0),
		Vector3(offset_x, 2.9, 0.0),
		Vector3(offset_x, 2.0, 1.3),
	]))
	return [moving, target]


func _body(space: RID, mesh: ArrayMesh, layer: int, mask: int) -> RID:
	var rid := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(rid, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(rid, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(rid, 0.7)
	PhysicsServer3D.soft_body_set_simulation_precision(rid, 10)
	PhysicsServer3D.soft_body_set_collision_layer(rid, layer)
	PhysicsServer3D.soft_body_set_collision_mask(rid, mask)
	PhysicsServer3D.soft_body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	# Keep the third corner anchored; the crossing edge remains dynamic.
	PhysicsServer3D.soft_body_pin_point(rid, 2, true)
	PhysicsServer3D.soft_body_set_space(rid, space)
	return rid


func _run() -> void:
	var errors: Array[String] = []
	var setting_base := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Expected Jolt Physics backend")
	for setting in ["soft_body_soft_contacts", "soft_body_soft_vertex_face_contacts",
					"soft_body_soft_edge_edge_contacts", "soft_body_soft_speculative_edge_ccd"]:
		if not bool(ProjectSettings.get_setting(setting_base + setting, false)):
			errors.append("Missing experimental setting: " + setting)
	if bool(ProjectSettings.get_setting(setting_base + "soft_body_soft_speculative_ccd", true)):
		errors.append("This fixture isolates swept EE: swept VF must be off")
	if not errors.is_empty():
		for err in errors:
			printerr(err)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	# Retain mesh resources throughout the simulation to keep RIDs valid.
	var meshes: Array[ArrayMesh] = []
	meshes.append_array(_pair_meshes(0.0))
	meshes.append_array(_pair_meshes(6.0))
	var bodies: Array[RID] = [
		_body(space, meshes[0], 1, 1),
		_body(space, meshes[1], 1, 1),
		_body(space, meshes[2], 2, 0),
		_body(space, meshes[3], 2, 0),
	]

	for warmup in range(2):
		await physics_frame
	var moving_a_before := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
	var moving_control_before := PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 0)
	var target_before := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var control_target_before := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)

	# An impulse at the dynamic soft body creates a displacement much
	# larger than the initial 0.38 m separation in one 60 Hz step.
	for idx in [0, 2]:
		PhysicsServer3D.soft_body_apply_central_impulse(bodies[idx], Vector3(0.0, 0.0, 35.0))
	var started := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame
		for j in range(bodies.size()):
			var bounds := PhysicsServer3D.soft_body_get_bounds(bodies[j])
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				errors.append("Nonfinite bounds in frame " + str(frame) + " body " + str(j))
				break
			for vertex in range(3):
				var position := PhysicsServer3D.soft_body_get_point_global_position(bodies[j], vertex)
				if not position.is_finite():
					errors.append("Nonfinite vertex in frame " + str(frame) + " body " + str(j))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

	var moving_a_after := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
	var moving_control_after := PhysicsServer3D.soft_body_get_point_global_position(bodies[2], 0)
	var target_after := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var control_target_after := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	var allowed_travel := moving_a_after.z - moving_a_before.z
	var control_travel := moving_control_after.z - moving_control_before.z
	var target_travel := target_after.z - target_before.z
	var control_target_travel := control_target_after.z - control_target_before.z
	if control_travel < 0.10:
		errors.append("Impulse failed to produce fast motion")
	if allowed_travel >= control_travel - 0.025:
		errors.append("Swept EE did not reduce travel relative to masked control")
	if target_travel <= control_target_travel + 0.005:
		errors.append("Swept EE did not transfer impulse to target edge")
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
		"allowed_travel_z": allowed_travel,
		"masked_travel_z": control_travel,
		"target_travel_z": target_travel,
		"masked_target_travel_z": control_target_travel,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt conservative swept soft-edge contacts and collision filters")
		quit(0)
	else:
		for err in errors:
			printerr(err)
		quit(1)
