extends SceneTree
## Jolt: validated convex tetrahedral volume fan + open-surface fallback.
## godot --headless --path tests/stress/jolt_volume --script res://convex_volume_regression.gd

const PREFIX := "JOLT_VOLUME_RESULT:"
const FRAMES := 100


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


func _tetra_volume(p: PackedVector3Array) -> float:
	return absf((p[1] - p[0]).cross(p[2] - p[0]).dot(p[3] - p[0])) / 6.0


func _vertex_positions(body: RID, count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(count):
		points.append(PhysicsServer3D.soft_body_get_point_global_position(body, i))
	return points


func _run() -> void:
	var errors: Array[String] = []
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics" or not bool(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_volume_preservation", false)):
		printerr("Jolt volume regression requires the Jolt-enabled project.godot")
		quit(1)
		return

	var tetra := _mesh(
		PackedVector3Array([
			Vector3(0, 3, 0),
			Vector3(1, 3, 0),
			Vector3(0, 4, 0),
			Vector3(0, 3, 1),
		]),
		PackedInt32Array([
			0, 2, 1,
			0, 1, 3,
			0, 3, 2,
			1, 2, 3,
		])
	)
	var open_mesh := _mesh(
		PackedVector3Array([
			Vector3(4, 3, 0),
			Vector3(5, 3, 0),
			Vector3(4, 3, 1),
			Vector3(5, 3, 1)
		]),
		PackedInt32Array([0, 2, 1, 1, 2, 3])
	)

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var solid := PhysicsServer3D.soft_body_create()
	var cloth := PhysicsServer3D.soft_body_create()

	for body in [solid, cloth]:
		PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
		PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.65)
		PhysicsServer3D.soft_body_set_collision_layer(body, 1)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)

	PhysicsServer3D.soft_body_set_mesh(solid, tetra.get_rid())
	PhysicsServer3D.soft_body_set_mesh(cloth, open_mesh.get_rid())
	PhysicsServer3D.soft_body_pin_point(solid, 0, true)
	PhysicsServer3D.soft_body_pin_point(cloth, 0, true)
	PhysicsServer3D.soft_body_set_space(solid, space)
	PhysicsServer3D.soft_body_set_space(cloth, space)
	for frame in range(3):
		await physics_frame

	var initial := _vertex_positions(solid, 4)
	var initial_volume := _tetra_volume(initial)
	if initial_volume < 0.01:
		errors.append("Invalid tetrahedron initial volume")

	var started_usec := Time.get_ticks_usec()
	PhysicsServer3D.soft_body_apply_central_impulse(solid, Vector3(0, -1.0, 0))
	for frame in range(FRAMES):
		await physics_frame
		var solid_positions := _vertex_positions(solid, 4)
		var cloth_positions := _vertex_positions(cloth, 4)
		var bounds_solid := PhysicsServer3D.soft_body_get_bounds(solid)
		var bounds_cloth := PhysicsServer3D.soft_body_get_bounds(cloth)
		if not bounds_solid.position.is_finite() or not bounds_solid.size.is_finite() or not bounds_cloth.position.is_finite() or not bounds_cloth.size.is_finite():
			errors.append("Invalid soft-body bounds at frame " + str(frame))
			break
		for p in solid_positions:
			if not p.is_finite():
				errors.append("Invalid solid particle at frame " + str(frame))
		for p in cloth_positions:
			if not p.is_finite():
				errors.append("Invalid open-cloth particle at frame " + str(frame))
		if not errors.is_empty():
			break

	var final_positions := _vertex_positions(solid, 4)
	var final_volume := _tetra_volume(final_positions)
	if not is_finite(final_volume) or final_volume < initial_volume * 0.05:
		errors.append("Tetrahedral volume collapsed")
	if final_volume > initial_volume * 4.0:
		errors.append("Tetrahedral volume expanded excessively")
	if not PhysicsServer3D.soft_body_is_point_pinned(solid, 0):
		errors.append("Pinned solid anchor lost")

	PhysicsServer3D.soft_body_set_space(solid, RID())
	PhysicsServer3D.soft_body_set_space(cloth, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(solid)
	PhysicsServer3D.free_rid(cloth)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"rest_volume": initial_volume,
		"final_volume": final_volume,
		"relative_volume": final_volume / maxf(initial_volume, 0.000001),
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: convex Jolt volume constraints and open-cloth fallback")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
