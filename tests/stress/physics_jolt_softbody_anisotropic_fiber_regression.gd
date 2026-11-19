extends SceneTree
## Jolt XPBD textile anisotropy: directional stretch compliance in the
## undeformed local mesh frame. Run with baseline/stiff/soft fiber options.

const PREFIX := "JOLT_SOFTBODY_ANISOTROPIC_FIBER_RESULT:"
const GRID := 12
const SPACING := 0.12
const FRAMES := 36
const FIBER_AXIS_SETTING := "physics/jolt_physics_3d/simulation/soft_body_fiber_axis"
const FIBER_MULTIPLIER_SETTING := "physics/jolt_physics_3d/simulation/soft_body_fiber_compliance_multiplier"


func _initialize() -> void:
	call_deferred("_run")


func _make_cloth() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in range(GRID):
		for col in range(GRID):
			vertices.append(Vector3((float(col) - float(GRID - 1) / 2.0) * SPACING,
					-float(row) * SPACING, 0.0))
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
	var axis := int(ProjectSettings.get_setting(FIBER_AXIS_SETTING, 0))
	var fiber_factor := float(ProjectSettings.get_setting(FIBER_MULTIPLIER_SETTING, 1.0))
	var errors: Array[String] = []
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Fixture requires the Jolt Physics backend")
	if axis < 0 or axis > 2 or not is_finite(fiber_factor) or fiber_factor < 0.1 or fiber_factor > 10.0:
		errors.append("Invalid anisotropic fiber material settings")
	if not errors.is_empty():
		printerr(str(errors))
		quit(1)
		return

	var mesh := _make_cloth()
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	var bodies: Array[RID] = []
	var initial_probes: Array[Vector3] = []
	var initial_pins: Array[Vector3] = []
	var probe_index := (GRID - 1) * GRID + int(GRID / 2)
	var pin_index := int(GRID / 2)
	var impulse := [Vector3(0.025, 0.0, 0.0), Vector3(0.0, -0.025, 0.0)]

	for index in range(2):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.4)
		PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
		PhysicsServer3D.soft_body_set_collision_layer(body, 1 << index)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		for col in range(GRID):
			PhysicsServer3D.soft_body_pin_point(body, col, true)
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)

	for frame in range(4):
		await physics_frame

	for body in bodies:
		initial_probes.append(PhysicsServer3D.soft_body_get_point_global_position(body, probe_index))
		initial_pins.append(PhysicsServer3D.soft_body_get_point_global_position(body, pin_index))

	var started := Time.get_ticks_usec()
	for index in range(bodies.size()):
		PhysicsServer3D.soft_body_apply_point_impulse(bodies[index], probe_index, impulse[index])
	for frame in range(FRAMES):
		await physics_frame

	var metrics: Array[Dictionary] = []
	for index in range(bodies.size()):
		var body := bodies[index]
		var probe := PhysicsServer3D.soft_body_get_point_global_position(body, probe_index)
		var pin := PhysicsServer3D.soft_body_get_point_global_position(body, pin_index)
		var bounds := PhysicsServer3D.soft_body_get_bounds(body)
		var probe_displacement := probe.distance_to(initial_probes[index])
		var pin_drift := pin.distance_to(initial_pins[index])
		if not probe.is_finite() or not pin.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():
			errors.append("Nonfinite cloth state for impulse direction " + str(index))
		elif probe_displacement > 30.0:
			errors.append("Unstable cloth deformation for impulse direction " + str(index))
		if pin_drift > 0.05:
			errors.append("Pinned textile edge moved for impulse direction " + str(index))
		metrics.append({
			"direction": "X" if index == 0 else "Y",
			"displacement": probe_displacement,
			"pinned_drift": pin_drift
		})
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"fiber_axis": axis,
		"fiber_compliance_multiplier": fiber_factor,
		"vertices_per_body": GRID * GRID,
		"triangles_per_body": 2 * (GRID - 1) * (GRID - 1),
		"frames": FRAMES,
		"cases": metrics,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("Jolt anisotropic cloth fiber regression passed.")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
