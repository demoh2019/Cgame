extends SceneTree
## XPBD cloth tethers: pins should remain fixed while the cloth hangs under
## gravity. CI runs this fixture separately in disabled, Euclidean and
## geodesic LRA modes selected via project settings before engine startup.

const PREFIX := "JOLT_SOFTBODY_LRA_RESULT:"
const SIDE := 12
const SPACING := 0.16
const STEP_COUNT := 90
const MULTIPLIER_SETTING := "physics/jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier"
const MODE_SETTING := "physics/jolt_physics_3d/simulation/soft_body_lra_mode"


func _initialize() -> void:
	call_deferred("_run")


func _build_cloth() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for y in range(SIDE):
		for x in range(SIDE):
			vertices.append(Vector3((float(x) - float(SIDE - 1) / 2.0) * SPACING,
					-float(y) * SPACING, 0.0))
	for y in range(SIDE - 1):
		for x in range(SIDE - 1):
			var a := y * SIDE + x
			indices.append_array(PackedInt32Array([a, a + SIDE, a + 1,
					a + 1, a + SIDE, a + SIDE + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	var mode := int(ProjectSettings.get_setting(MODE_SETTING, 0))
	var length_factor := float(ProjectSettings.get_setting(MULTIPLIER_SETTING, 1.0))
	var errors: Array[String] = []
	if mode < 0 or mode > 2:
		errors.append("Invalid LRA mode in project settings")
	if length_factor < 1.0 or not is_finite(length_factor):
		errors.append("Invalid LRA max distance multiplier")

	var mesh := _build_cloth()
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_collision_layer(body, 1)
	PhysicsServer3D.soft_body_set_collision_mask(body, 0)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	# LRA constraints are generated at creation: mark the top edge
	# kinematic BEFORE inserting the soft body into the physics space.
	for x in range(SIDE):
		PhysicsServer3D.soft_body_pin_point(body, x, true)
	PhysicsServer3D.soft_body_set_space(body, space)

	var upper_probe := int(SIDE / 2)
	var lower_probe := (SIDE - 1) * SIDE + upper_probe
	var pinned_start := PhysicsServer3D.soft_body_get_point_global_position(body, upper_probe)
	var original_tail := PhysicsServer3D.soft_body_get_point_global_position(body, lower_probe)
	var started := Time.get_ticks_usec()
	for frame in range(STEP_COUNT):
		await physics_frame

	var pinned_end := PhysicsServer3D.soft_body_get_point_global_position(body, upper_probe)
	var tail_end := PhysicsServer3D.soft_body_get_point_global_position(body, lower_probe)
	var bounds := PhysicsServer3D.soft_body_get_bounds(body)
	var pinned_drift := pinned_end.distance_to(pinned_start)
	var anchor_distance := pinned_end.distance_to(tail_end)
	var original_distance := pinned_start.distance_to(original_tail)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0

	if not pinned_end.is_finite() or not tail_end.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():
		errors.append("Nonfinite simulated cloth points or bounds")
	if pinned_drift > 0.08:
		errors.append("Pinned edge moved more than expected")
	# Euclidean and geodesic tethers should prevent runaway stretch,
	# while allowing normal XPBD solver error and triangle deformation.
	if mode > 0 and anchor_distance > original_distance * length_factor + 0.45:
		errors.append("Tethered cloth stretched beyond a conservative limit")

	PhysicsServer3D.soft_body_set_space(body, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"mode": mode,
		"max_distance_multiplier": length_factor,
		"vertices": SIDE * SIDE,
		"triangles": 2 * (SIDE - 1) * (SIDE - 1),
		"steps": STEP_COUNT,
		"pinned_drift": pinned_drift,
		"initial_anchor_distance": original_distance,
		"final_anchor_distance": anchor_distance,
		"elapsed_ms": elapsed_ms,
		"errors": errors
	}))
	if errors.is_empty():
		print("Jolt soft-body LRA regression passed.")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
