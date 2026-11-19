extends SceneTree
## Native Jolt self-edge CCD regression. A fast deformable edge approaches
## a perpendicular pinned edge inside ONE soft body. The control soft body
## has the same topology, masses, impulses and spring lengths, but its
## second triangle is shifted 3 m in X so no self collision is possible.
## Run --headless --path tests/stress/jolt_soft_self_edge_sweep --script res://swept_self_edges_regression.gd

const PREFIX := "JOLT_SWEPT_SELF_EDGES_RESULT:"
const FRAMES := 6
const ENDPOINT_IMPULSE := Vector3(0.0, 0.0, 7.0)


func _initialize() -> void:
	call_deferred("_run")


func _triangle_pair_mesh(x_offset: float, avoid_crossing: bool) -> ArrayMesh:
	var target_x := x_offset + (3.0 if avoid_crossing else 0.0)
	var vertices := PackedVector3Array([
		Vector3(x_offset - 0.9, 2.0, -0.38),
		Vector3(x_offset + 0.9, 2.0, -0.38),
		Vector3(x_offset, 2.0, -1.3),
		Vector3(target_x, 1.1, 0.0),
		Vector3(target_x, 2.9, 0.0),
		Vector3(target_x, 2.0, 1.3),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _body(space: RID, mesh: ArrayMesh) -> RID:
	var rid := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(rid, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(rid, 1.2)
	PhysicsServer3D.soft_body_set_linear_stiffness(rid, 0.6)
	PhysicsServer3D.soft_body_set_simulation_precision(rid, 8)
	PhysicsServer3D.soft_body_set_collision_layer(rid, 0)
	PhysicsServer3D.soft_body_set_collision_mask(rid, 0)
	PhysicsServer3D.soft_body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	for point in [2, 3, 4, 5]:
		PhysicsServer3D.soft_body_pin_point(rid, point, true)
	PhysicsServer3D.soft_body_set_space(rid, space)
	return rid


func _run() -> void:
	var errors: Array[String] = []
	var prefix := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Jolt backend required")
	for key in ["soft_body_self_contacts", "soft_body_self_edge_contacts", "soft_body_self_speculative_edge_ccd"]:
		if not bool(ProjectSettings.get_setting(prefix + key, false)):
			errors.append("Missing self-edge CCD setting: " + key)
	if bool(ProjectSettings.get_setting(prefix + "soft_body_soft_contacts", true)):
		errors.append("Inter-body collision must be disabled in this fixture")
	if bool(ProjectSettings.get_setting(prefix + "soft_body_self_position_projection", true)):
		errors.append("Self position correction must be disabled to isolate swept EE impulse")
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [
		_triangle_pair_mesh(0.0, false),
		_triangle_pair_mesh(7.0, true),
	]
	var bodies: Array[RID] = [
		_body(space, meshes[0]),
		_body(space, meshes[1]),
	]
	for warmup in range(2):
		await physics_frame

	var initial_hit := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
	var initial_control := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	for body in bodies:
		for point in [0, 1]:
			PhysicsServer3D.soft_body_apply_point_impulse(body, point, ENDPOINT_IMPULSE)

	var peak_colliding_motion := 0.0
	var peak_control_motion := 0.0
	var start_usec := Time.get_ticks_usec()

	for frame in range(FRAMES):
		await physics_frame
		for j in range(bodies.size()):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[j])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Nonfinite soft-body AABB in frame " + str(frame))
				break
			for vertex in range(6):
				var p := PhysicsServer3D.soft_body_get_point_global_position(bodies[j], vertex)
				if not p.is_finite():
					errors.append("Nonfinite soft vertex " + str(vertex))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

		var colliding := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
		var control := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
		peak_colliding_motion = maxf(peak_colliding_motion, colliding.z - initial_hit.z)
		peak_control_motion = maxf(peak_control_motion, control.z - initial_control.z)

	if peak_control_motion < 0.18:
		errors.append("Fast unopposed edge did not advance enough to test tunneling")
	if peak_colliding_motion >= peak_control_motion - 0.015:
		errors.append("Swept self-edge contact did not reduce edge travel against control")
	for body in bodies:
		for pin in [2, 3, 4, 5]:
			if not PhysicsServer3D.soft_body_is_point_pinned(body, pin):
				errors.append("Pinned triangle vertex released: " + str(pin))
	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"peak_colliding_edge_z": peak_colliding_motion,
		"peak_unopposed_edge_z": peak_control_motion,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt swept self edge-edge CCD versus unopposed control")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
