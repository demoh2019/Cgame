extends SceneTree
## Jolt soft-body long-range geodesic attachment regression.
## Run with a Cgame binary supporting Jolt:
## godot --headless --path tests/stress/jolt_lra --script res://pinned_cloth_lra_regression.gd

const PREFIX := "JOLT_SOFTBODY_LRA_RESULT:"
const GRID := 12
const SPACING := 0.2
const DUP_SOURCE := GRID + 1
const DUP_INDEX := GRID * GRID
const FRAMES := 75

func _initialize() -> void:
	call_deferred("_run")


func _make_cloth() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(GRID):
		for x in range(GRID):
			vertices.append(Vector3(float(x) * SPACING, 2.0, float(z) * SPACING))
	# A second visual index with an identical position, but both indices are
	# referenced by different triangles. Jolt should weld them for physics.
	vertices.append(vertices[DUP_SOURCE])

	for z in range(GRID - 1):
		for x in range(GRID - 1):
			var a := z * GRID + x
			var b := a + 1
			var c := a + GRID
			var d := c + 1
			var first := DUP_INDEX if a == DUP_SOURCE else a
			indices.append_array(PackedInt32Array([first, c, b, b, c, d]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	var errors: Array[String] = []
	var configured_engine := str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	var mode := int(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_lra_mode", 0))
	var slack := float(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier", 0.0))
	if configured_engine != "Jolt Physics" or mode != 2 or absf(slack - 1.05) > 0.0001:
		printerr("Invalid Jolt geodesic LRA test project configuration")
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var cloth_mesh := _make_cloth()
	var cloth := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(cloth, cloth_mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(cloth, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(cloth, 0.25)
	PhysicsServer3D.soft_body_set_simulation_precision(cloth, 8)
	PhysicsServer3D.soft_body_set_state(cloth, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.soft_body_set_collision_layer(cloth, 1)
	PhysicsServer3D.soft_body_set_collision_mask(cloth, 0)

	# Pin *before* creating the Jolt soft body: LRA topology is computed
	# once from the initial anchored mesh.
	for x in range(GRID):
		PhysicsServer3D.soft_body_pin_point(cloth, x, true)
	PhysicsServer3D.soft_body_pin_point(cloth, DUP_SOURCE, true)
	PhysicsServer3D.soft_body_set_space(cloth, space)

	if not PhysicsServer3D.soft_body_is_point_pinned(cloth, DUP_SOURCE):
		errors.append("Source of welded mesh alias was not pinned")
	if not PhysicsServer3D.soft_body_is_point_pinned(cloth, DUP_INDEX):
		errors.append("Welded visual alias did not inherit physical pin")

	var pinned_start := PhysicsServer3D.soft_body_get_point_global_position(cloth, DUP_SOURCE)
	var alias_start := PhysicsServer3D.soft_body_get_point_global_position(cloth, DUP_INDEX)
	if pinned_start.distance_to(alias_start) > 0.00001:
		errors.append("Visual aliases did not map to the same physical particle")
	var far_index := GRID * (GRID - 1) + GRID / 2
	var far_start := PhysicsServer3D.soft_body_get_point_global_position(cloth, far_index)

	var start_usec := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame
		var anchor := PhysicsServer3D.soft_body_get_point_global_position(cloth, DUP_SOURCE)
		var alias := PhysicsServer3D.soft_body_get_point_global_position(cloth, DUP_INDEX)
		var far := PhysicsServer3D.soft_body_get_point_global_position(cloth, far_index)
		var bounds := PhysicsServer3D.soft_body_get_bounds(cloth)
		if not anchor.is_finite() or not alias.is_finite() or not far.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():
			errors.append("Nonfinite soft body state on frame " + str(frame))
			break
		if anchor.distance_to(pinned_start) > 0.001 or alias.distance_to(pinned_start) > 0.001:
			errors.append("Pinned weld alias drift on frame " + str(frame))
			break

	var far_end := PhysicsServer3D.soft_body_get_point_global_position(cloth, far_index)
	if far_end.distance_to(far_start) > 30.0:
		errors.append("Cloth displacement exceeds stability limit")

	PhysicsServer3D.soft_body_set_space(cloth, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(cloth)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"grid_vertices": GRID * GRID,
		"lra_mode": mode,
		"distance_multiplier": slack,
		"far_vertex_displacement": far_end.distance_to(far_start),
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt pinned cloth geodesic LRA and welded vertex aliases")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
