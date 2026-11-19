extends SceneTree
## Jolt soft body accelerated vertex-face contacts with a deformable grid
## (98 triangles triggers the BVH path). Collision-masked pair is the control.
## godot --headless --path tests/stress/jolt_soft_soft_bvh --script res://bvh_regression.gd

const PREFIX := "JOLT_SOFT_SOFT_BVH_RESULT:"
const GRID := 8
const FRAMES := 45


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


func _grid_mesh(center_x: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(GRID):
		for x in range(GRID):
			vertices.append(Vector3(center_x - 1.0 + 2.0 * x / (GRID - 1), 2.0, -1.0 + 2.0 * z / (GRID - 1)))
	for z in range(GRID - 1):
		for x in range(GRID - 1):
			var a := z * GRID + x
			var b := a + 1
			var c := a + GRID
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return _mesh(vertices, indices)


func _tetra_mesh(center_x: float) -> ArrayMesh:
	return _mesh(PackedVector3Array([
		Vector3(center_x, 2.055, 0),
		Vector3(center_x + 0.3, 2.4, 0),
		Vector3(center_x - 0.3, 2.4, 0),
		Vector3(center_x, 2.4, 0.25),
	]), PackedInt32Array([0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]))


func _body(space: RID, mesh: ArrayMesh, layer: int, mask: int, grid: bool) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.6)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 10)
	PhysicsServer3D.soft_body_set_collision_layer(body, layer)
	PhysicsServer3D.soft_body_set_collision_mask(body, mask)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	if grid:
		PhysicsServer3D.soft_body_pin_point(body, 0, true)
		PhysicsServer3D.soft_body_pin_point(body, GRID - 1, true)
		PhysicsServer3D.soft_body_pin_point(body, GRID * (GRID - 1), true)
		PhysicsServer3D.soft_body_pin_point(body, GRID * GRID - 1, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var root := "physics/jolt_physics_3d/simulation/"
	for name in ["soft_body_soft_contacts", "soft_body_soft_vertex_face_contacts", "soft_body_soft_vertex_face_bvh"]:
		if not bool(ProjectSettings.get_setting(root + name, false)):
			errors.append(name + " disabled")
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Jolt Physics backend required")
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	# Hold mesh references for the entire scene.
	var meshes: Array[ArrayMesh] = [
		_grid_mesh(0.0), _tetra_mesh(0.0), _grid_mesh(6.0), _tetra_mesh(6.0)
	]
	var bodies: Array[RID] = [
		_body(space, meshes[0], 1, 1, true),
		_body(space, meshes[1], 1, 1, false),
		_body(space, meshes[2], 2, 0, true),
		_body(space, meshes[3], 2, 0, false),
	]

	for frame in range(2):
		await physics_frame
	var tip_start := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var masked_start := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	var started_usec := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame
		for j in range(bodies.size()):
			var aabb := PhysicsServer3D.soft_body_get_bounds(bodies[j])
			if not aabb.position.is_finite() or not aabb.size.is_finite():
				errors.append("Nonfinite body bounds at frame " + str(frame))
				break
			for v in range(GRID * GRID if j % 2 == 0 else 4):
				var position := PhysicsServer3D.soft_body_get_point_global_position(bodies[j], v)
				if not position.is_finite():
					errors.append("Nonfinite vertex at frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

	var tip_end := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	var masked_end := PhysicsServer3D.soft_body_get_point_global_position(bodies[3], 0)
	var allowed_lift := tip_end.y - tip_start.y
	var masked_lift := masked_end.y - masked_start.y
	if allowed_lift < masked_lift + 0.01:
		errors.append("BVH contact did not separate penetrating soft bodies")
	if absf(masked_lift) > 0.04:
		errors.append("Masked control moved")

	for j in [0, 2]:
		for i in [0, GRID - 1, GRID * (GRID - 1), GRID * GRID - 1]:
			if not PhysicsServer3D.soft_body_is_point_pinned(bodies[j], i):
				errors.append("Grid pin lost")

	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"faces_per_grid": 2 * (GRID - 1) * (GRID - 1),
		"frames": FRAMES,
		"allowed_lift": allowed_lift,
		"masked_lift": masked_lift,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt bounded BVH soft-soft vertex-face contacts")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
