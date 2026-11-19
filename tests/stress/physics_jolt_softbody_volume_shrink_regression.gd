extends SceneTree
## Advanced Jolt soft-body volume physics: optional isotropic rest-volume
## contraction/expansion vs the existing incompressible volume mode.

const PREFIX := "JOLT_SOFTBODY_VOLUME_SHRINK_RESULT:"
const SETTING := "physics/jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor"
const VOLUME_SETTING := "physics/jolt_physics_3d/simulation/soft_body_volume_preservation"
const RADIAL_SETTING := "physics/jolt_physics_3d/simulation/soft_body_volume_radial_springs"
const SHRINK_VALUES := [-0.15, 0.0, 0.25]
const FRAMES := 90


func _initialize() -> void:
	call_deferred("_run")


func _make_tetrahedron() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 2.0, 0.0),
		Vector3(1.0, 2.0, 0.0),
		Vector3(0.0, 3.0, 0.0),
		Vector3(0.0, 2.0, 1.0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _tetra_volume(p: PackedVector3Array) -> float:
	return absf((p[1] - p[0]).cross(p[2] - p[0]).dot(p[3] - p[0])) / 6.0


func _positions(body: RID) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	for index in range(4):
		vertices.append(PhysicsServer3D.soft_body_get_point_global_position(body, index))
	return vertices


func _run() -> void:
	var enabled := bool(ProjectSettings.get_setting(SETTING, false))
	var radial_enabled := bool(ProjectSettings.get_setting(RADIAL_SETTING, false))
	var backend := str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	if backend != "Jolt Physics" or not bool(ProjectSettings.get_setting(VOLUME_SETTING, false)):
		printerr("Jolt volume shrink regression requires the Jolt volume-preservation backend")
		quit(1)
		return

	var errors: Array[String] = []
	var mesh := _make_tetrahedron()
	var rest_mesh := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0),
		Vector3(1.0, 2.0, 0.0),
		Vector3(0.0, 3.0, 0.0),
		Vector3(0.0, 2.0, 1.0)
	])
	var rest_volume := _tetra_volume(rest_mesh)
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	var bodies: Array[RID] = []
	var pin_starts: Array[Vector3] = []

	for case_index in range(SHRINK_VALUES.size()):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.35)
		PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
		PhysicsServer3D.soft_body_set_shrinking_factor(body, SHRINK_VALUES[case_index])
		PhysicsServer3D.soft_body_set_collision_layer(body, 1 << case_index)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.soft_body_pin_point(body, 0, true)
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)
		pin_starts.append(PhysicsServer3D.soft_body_get_point_global_position(body, 0))

	var started := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame

	var metrics: Array[Dictionary] = []
	for case_index in range(bodies.size()):
		var body := bodies[case_index]
		var vertices := _positions(body)
		var bounds := PhysicsServer3D.soft_body_get_bounds(body)
		var shrink := float(SHRINK_VALUES[case_index])
		var expected_volume := rest_volume * pow(1.0 - shrink, 3.0) if enabled else rest_volume
		var measured_volume := _tetra_volume(vertices)
		var pin_drift := vertices[0].distance_to(pin_starts[case_index])
		var all_finite := bounds.position.is_finite() and bounds.size.is_finite()
		for vertex in vertices:
			all_finite = all_finite and vertex.is_finite()
		if not all_finite or not is_finite(measured_volume):
			errors.append("Nonfinite soft-body volume state for shrink " + str(shrink))
		elif measured_volume < rest_volume * 0.01 or measured_volume > rest_volume * 5.0:
			errors.append("Extreme volume collapse/expansion for shrink " + str(shrink))
		if pin_drift > 0.05:
			errors.append("Pinned volume anchor moved for shrink " + str(shrink))
		metrics.append({
			"shrink": shrink,
			"target_volume": expected_volume,
			"measured_volume": measured_volume,
			"pinned_drift": pin_drift
		})
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)
	print(PREFIX + JSON.stringify({
		"follow_shrinking_factor": enabled,
		"radial_springs": radial_enabled,
		"rest_volume": rest_volume,
		"frames": FRAMES,
		"cases": metrics,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("Jolt soft-body volumetric shrink regression passed.")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
