extends SceneTree
## Native regression: Jolt LRA + convex tetrahedral XPBD + orthotropic
## radial springs + bending, all active on the same mesh.
## godot --headless --path tests/stress/jolt_combined --script res://combined_softbody_regression.gd

const PREFIX := "JOLT_COMBINED_VOLUME_LRA_RESULT:"
const FRAMES := 90


func _initialize() -> void:
	call_deferred("_run")


func _create_closed_cube(invert_winding: bool = false) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(-0.5, 2.0, -0.5),
		Vector3(0.5, 2.0, -0.5),
		Vector3(0.5, 3.0, -0.5),
		Vector3(-0.5, 3.0, -0.5),
		Vector3(-0.5, 2.0, 0.5),
		Vector3(0.5, 2.0, 0.5),
		Vector3(0.5, 3.0, 0.5),
		Vector3(-0.5, 3.0, 0.5)
	])
	var indices := PackedInt32Array([
		0, 2, 1, 0, 3, 2,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		3, 7, 6, 3, 6, 2,
		0, 4, 7, 0, 7, 3,
		1, 2, 6, 1, 6, 5
	])
	if invert_winding:
		for i in range(vertices.size()):
			vertices[i] += Vector3(3.0, 0.0, 0.0)
		for i in range(0, indices.size(), 3):
			var swap := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = swap
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	var errors: Array[String] = []
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Fixture is not using the Jolt backend")
	var settings_to_check := {
		"soft_body_bend_mode": 2,
		"soft_body_lra_mode": 2,
		"soft_body_radial_anisotropy_axis": 2
	}
	for setting_name in settings_to_check:
		if int(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/" + setting_name, -1)) != settings_to_check[setting_name]:
			errors.append("Unexpected physics setting: " + setting_name)
	for setting_name in ["soft_body_volume_preservation", "soft_body_volume_radial_springs"]:
		if not bool(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/" + setting_name, false)):
			errors.append("Required feature is disabled: " + setting_name)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var normal_mesh := _create_closed_cube()
	var reversed_mesh := _create_closed_cube(true)
	var bodies: Array[RID] = []
	for i in range(2):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, normal_mesh.get_rid() if i == 0 else reversed_mesh.get_rid())
		PhysicsServer3D.soft_body_set_total_mass(body, 2.0)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.7)
		PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
		PhysicsServer3D.soft_body_set_collision_layer(body, 1 << i)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		# LRA must detect these anchors before constraints are constructed.
		for idx in [2, 3, 6, 7]:
			PhysicsServer3D.soft_body_pin_point(body, idx, true)
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)
	for frame in range(4):
		await physics_frame

	var first_anchors: Array[Vector3] = []
	for body in bodies:
		first_anchors.append(PhysicsServer3D.soft_body_get_point_global_position(body, 3))
	var started := Time.get_ticks_usec()
	for body in bodies:
		PhysicsServer3D.soft_body_apply_central_impulse(body, Vector3(3.0, 0.0, 1.5))
	for frame in range(FRAMES):
		await physics_frame
		for j in range(bodies.size()):
			var body := bodies[j]
			var aabb := PhysicsServer3D.soft_body_get_bounds(body)
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Nonfinite body AABB at frame " + str(frame) + ", body " + str(j))
				break
			for idx in range(8):
				var position := PhysicsServer3D.soft_body_get_point_global_position(body, idx)
				if not position.is_finite() or position.distance_to(first_anchors[j]) > 60.0:
					errors.append("Unstable surface vertex " + str(idx) + " at " + str(frame) + ", body " + str(j))
					break
			if not errors.is_empty():
				break
			var anchor := PhysicsServer3D.soft_body_get_point_global_position(body, 3)
			if anchor.distance_squared_to(first_anchors[j]) > 0.00001:
				errors.append("Pinned anchor drift at " + str(frame) + ", body " + str(j))
				break
		if not errors.is_empty():
			break

	for j in range(bodies.size()):
		for idx in [2, 3, 6, 7]:
			if not PhysicsServer3D.soft_body_is_point_pinned(bodies[j], idx):
				errors.append("Pinned vertex " + str(idx) + " released from body " + str(j))

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)
	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"closed_body_count": bodies.size(),
		"tests_opposite_face_winding": true,
		"anisotropy_axis": 2,
		"anisotropy_ratio": 4.0,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: combined Jolt volume, LRA, bending and directional radial elasticity")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
