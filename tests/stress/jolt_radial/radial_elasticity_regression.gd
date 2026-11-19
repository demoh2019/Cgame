extends SceneTree
## Native radial elastic volume constraint smoke regression.
## --headless --path tests/stress/jolt_radial --script res://radial_elasticity_regression.gd
## Run with a compiled Cgame Jolt-enabled editor.

const PREFIX := "JOLT_RADIAL_ELASTICITY_RESULT:"
const FRAMES := 120


func _initialize() -> void:
	call_deferred("_run")


func _make_cube() -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(-0.5, 1.5, -0.5),
		Vector3(0.5, 1.5, -0.5),
		Vector3(0.5, 2.5, -0.5),
		Vector3(-0.5, 2.5, -0.5),
		Vector3(-0.5, 1.5, 0.5),
		Vector3(0.5, 1.5, 0.5),
		Vector3(0.5, 2.5, 0.5),
		Vector3(-0.5, 2.5, 0.5),
	])
	# Closed cube with outward consistent triangle winding.
	var indices := PackedInt32Array([
		0, 2, 1, 0, 3, 2,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		3, 7, 6, 3, 6, 2,
		0, 4, 7, 0, 7, 3,
		1, 2, 6, 1, 6, 5,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	var errors: Array[String] = []
	var enabled := bool(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_volume_radial_springs", false))
	var compliance := float(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_volume_radial_compliance", -1.0))
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics" or not enabled or absf(compliance - 0.0001) > 0.0000001:
		printerr("Expected Jolt radial elastic volume test settings")
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var mesh := _make_cube()
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_total_mass(body, 2.0)
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.8)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 12)
	PhysicsServer3D.soft_body_set_collision_layer(body, 1)
	PhysicsServer3D.soft_body_set_collision_mask(body, 0)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	# Pin before assigning the space so the surface+volume topology is
	# constructed with a valid kinematic anchor.
	PhysicsServer3D.soft_body_pin_point(body, 3, true)
	PhysicsServer3D.soft_body_pin_point(body, 6, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	for frame in range(4):
		await physics_frame
	var initial_anchor := PhysicsServer3D.soft_body_get_point_global_position(body, 3)
	var initial_free := PhysicsServer3D.soft_body_get_point_global_position(body, 0)
	var started_usec := Time.get_ticks_usec()
	PhysicsServer3D.soft_body_apply_central_impulse(body, Vector3(6, 0, 2))
	for frame in range(FRAMES):
		await physics_frame
		var bounds := PhysicsServer3D.soft_body_get_bounds(body)
		if not bounds.position.is_finite() or not bounds.size.is_finite():
			errors.append("Nonfinite world bounds at frame " + str(frame))
			break
		for i in range(8):
			var pos := PhysicsServer3D.soft_body_get_point_global_position(body, i)
			if not pos.is_finite() or pos.distance_to(initial_anchor) > 100.0:
				errors.append("Unstable or nonfinite vertex " + str(i) + ", frame " + str(frame))
				break
		if not errors.is_empty():
			break
		if PhysicsServer3D.soft_body_get_point_global_position(body, 3).distance_to(initial_anchor) > 0.001:
			errors.append("Pinned elastic solid anchor drift at frame " + str(frame))
			break
	var final_free := PhysicsServer3D.soft_body_get_point_global_position(body, 0)
	if not PhysicsServer3D.soft_body_is_point_pinned(body, 6):
		errors.append("Lost second pinned vertex")

	PhysicsServer3D.soft_body_set_space(body, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"radial_compliance": compliance,
		"free_vertex_displacement": final_free.distance_to(initial_free),
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: radial convex soft-body elasticity stability")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
