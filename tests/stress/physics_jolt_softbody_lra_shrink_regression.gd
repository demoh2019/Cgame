extends SceneTree
## Check that Jolt XPBD long-range attachments shrink/expand consistently
## with ordinary cloth rest-length constraints in Euclidean/geodesic modes.

const PREFIX := "JOLT_SOFTBODY_LRA_SHRINK_RESULT:"
const GRID := 12
const SPACING := 0.16
const FRAMES := 90
const SHRINK_VALUES := [-0.15, 0.0, 0.25]
const MODE_SETTING := "physics/jolt_physics_3d/simulation/soft_body_lra_mode"
const SLACK_SETTING := "physics/jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier"


func _initialize() -> void:
	call_deferred("_run")


func _make_cloth() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in range(GRID):
		for col in range(GRID):
			vertices.append(Vector3(float(col) * SPACING, 2.0 - float(row) * SPACING, 0.0))
	for row in range(GRID - 1):
		for col in range(GRID - 1):
			var a := row * GRID + col
			indices.append_array(PackedInt32Array([
				a, a + GRID, a + 1,
				a + 1, a + GRID, a + GRID + 1
			]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	var mode := int(ProjectSettings.get_setting(MODE_SETTING, 0))
	var slack := float(ProjectSettings.get_setting(SLACK_SETTING, 1.0))
	var backend := str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	var errors: Array[String] = []
	if backend != "Jolt Physics" or mode < 1 or mode > 2:
		printerr("This regression requires Jolt and Euclidean/Geodesic LRA mode")
		quit(1)
		return

	var mesh := _make_cloth()
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var bodies: Array[RID] = []
	var pin_starts: Array[Vector3] = []
	var tail_starts: Array[Vector3] = []
	var pin_index := int(GRID / 2)
	var tail_index := (GRID - 1) * GRID + pin_index

	for case_idx in range(SHRINK_VALUES.size()):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.3)
		PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
		PhysicsServer3D.soft_body_set_shrinking_factor(body, SHRINK_VALUES[case_idx])
		PhysicsServer3D.soft_body_set_collision_layer(body, 1 << case_idx)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		for col in range(GRID):
			PhysicsServer3D.soft_body_pin_point(body, col, true)
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)
		pin_starts.append(PhysicsServer3D.soft_body_get_point_global_position(body, pin_index))
		tail_starts.append(PhysicsServer3D.soft_body_get_point_global_position(body, tail_index))

	var started := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame

	var metrics: Array[Dictionary] = []
	for case_idx in range(bodies.size()):
		var body := bodies[case_idx]
		var start_distance := pin_starts[case_idx].distance_to(tail_starts[case_idx])
		var pin_end := PhysicsServer3D.soft_body_get_point_global_position(body, pin_index)
		var tail_end := PhysicsServer3D.soft_body_get_point_global_position(body, tail_index)
		var bounds := PhysicsServer3D.soft_body_get_bounds(body)
		var pin_drift := pin_end.distance_to(pin_starts[case_idx])
		var actual_distance := pin_end.distance_to(tail_end)
		var target_limit := start_distance * (1.0 - SHRINK_VALUES[case_idx]) * slack
		if not pin_end.is_finite() or not tail_end.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():
			errors.append("Nonfinite position/bounds for shrink " + str(SHRINK_VALUES[case_idx]))
		if pin_drift > 0.05:
			errors.append("Pinned vertex drift for shrink " + str(SHRINK_VALUES[case_idx]))
		# Allow for XPBD solver error and a changing cloth shape; this is
		# intentionally a conservative instability guard, not a proof of
		# a particular equilibrium shape or a microbenchmark speedup.
		if actual_distance > target_limit + 0.45:
			errors.append("LRA maximum distance exceeded for shrink " + str(SHRINK_VALUES[case_idx]))
		metrics.append({
			"shrink": SHRINK_VALUES[case_idx],
			"initial_distance": start_distance,
			"final_distance": actual_distance,
			"expected_tether_limit": target_limit,
			"pinned_drift": pin_drift
		})
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)
	print(PREFIX + JSON.stringify({
		"mode": mode,
		"slack": slack,
		"frames": FRAMES,
		"cases": metrics,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("Jolt soft-body LRA shrink regression passed.")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
