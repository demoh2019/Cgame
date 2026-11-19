extends SceneTree
## Native stress/regression for predictive soft-soft point-triangle collision.
## A fast tetrahedron starts ABOVE a pinned 8x8 soft grid. It traverses the
## grid during a single 60 Hz step without predictive contacts. The same
## geometry is duplicated with masks disabled to serve as the control.
## Run --headless --path tests/stress/jolt_soft_soft_sweep --script res://swept_triangle_regression.gd

const PREFIX := "JOLT_SOFT_SWEPT_CONTACT_RESULT:"
const GRID := 8
const FRAMES := 3


func _initialize() -> void:
	call_deferred("_run")


func _create_mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _grid_mesh(x_offset: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(GRID):
		for x in range(GRID):
			vertices.append(Vector3(x_offset - 1.0 + 2.0 * x / (GRID - 1), 2.0, -1.0 + 2.0 * z / (GRID - 1)))
	for z in range(GRID - 1):
		for x in range(GRID - 1):
			var a := z * GRID + x
			indices.append_array(PackedInt32Array([a, a + GRID, a + 1, a + 1, a + GRID, a + GRID + 1]))
	return _create_mesh(vertices, indices)


func _tetra_mesh(x: float) -> ArrayMesh:
	return _create_mesh(PackedVector3Array([
		Vector3(x, 2.38, 0.0),
		Vector3(x + 0.23, 2.80, 0.0),
		Vector3(x - 0.23, 2.80, 0.0),
		Vector3(x, 2.80, 0.23),
	]), PackedInt32Array([0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]))


func _make_body(space: RID, mesh: ArrayMesh, layer: int, mask: int, grid: bool) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 100.0 if grid else 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.8)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
	PhysicsServer3D.soft_body_set_collision_layer(body, layer)
	PhysicsServer3D.soft_body_set_collision_mask(body, mask)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	if grid:
		for idx in [0, GRID - 1, GRID * (GRID - 1), GRID * GRID - 1]:
			PhysicsServer3D.soft_body_pin_point(body, idx, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var base := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Jolt physics backend required")
	for setting in ["soft_body_soft_contacts", "soft_body_soft_vertex_face_contacts", "soft_body_soft_vertex_face_bvh", "soft_body_soft_speculative_ccd"]:
		if not bool(ProjectSettings.get_setting(base + setting, false)):
			errors.append("Missing required setting: " + setting)
	if not errors.is_empty():
		for err in errors:
			printerr(err)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [_grid_mesh(0.0), _tetra_mesh(0.0), _grid_mesh(6.0), _tetra_mesh(6.0)]
	var bodies: Array[RID] = [
		_make_body(space, meshes[0], 1, 1, true),
		_make_body(space, meshes[1], 1, 1, false),
		_make_body(space, meshes[2], 2, 0, true),
		_make_body(space, meshes[3], 2, 0, false),
	]

	for frame in range(2):
		await physics_frame
	var before := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var before_masked := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	# 35 m/s downward: one fixed step travels 0.58 m, larger than the
	# initial 0.38 m separation from the cloth.
	for idx in [1, 3]:
		PhysicsServer3D.soft_body_apply_central_impulse(bodies[idx], Vector3(0, -35.0, 0))

	var start := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame
		for body_idx in range(4):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[body_idx])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Nonfinite AABB at frame " + str(frame) + " body " + str(body_idx))
				break
			for point_idx in range(GRID * GRID if body_idx % 2 == 0 else 4):
				if not PhysicsServer3D.soft_body_get_point_global_position(bodies[body_idx], point_idx).is_finite():
					errors.append("Nonfinite soft particle at frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

	var after := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var masked := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	var allowed_drop := before.y - after.y
	var masked_drop := before_masked.y - masked.y
	if masked_drop < 0.30:
		errors.append("Reference impulse did not generate fast soft-body motion")
	if allowed_drop >= masked_drop - 0.15:
		errors.append("Swept contact did not appreciably slow the fast penetrating body")
	for i in [0, 2]:
		for index in [0, GRID - 1, GRID * (GRID - 1), GRID * GRID - 1]:
			if not PhysicsServer3D.soft_body_is_point_pinned(bodies[i], index):
				errors.append("Pinned cloth corner released")

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"faces_per_grid": 2 * (GRID - 1) * (GRID - 1),
		"allowed_drop": allowed_drop,
		"masked_drop": masked_drop,
		"errors": errors,
		"elapsed_ms": float(Time.get_ticks_usec() - start) / 1000.0
	}))
	if errors.is_empty():
		print("PASS: Jolt speculative swept soft vertex-face contact with masked control")
		quit(0)
	else:
		for err in errors:
			printerr(err)
		quit(1)
