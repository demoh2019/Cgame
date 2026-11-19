extends SceneTree
## Large cloth meshes with duplicated vertex positions and repeated indices:
## verify Jolt mesh-to-physics mapping and record construction cost.

const PREFIX := "JOLT_SOFTBODY_VERTEX_DEDUP_RESULT:"
const GRID := 24
const WAVES := 3
const BODIES_PER_WAVE := 3
const GRID_VERTEX_COUNT := GRID * GRID
const PROBE_INDEX := 10 * GRID + 10


func _initialize() -> void:
	call_deferred("_exercise")


func _build_cloth() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for y in range(GRID):
		for x in range(GRID):
			vertices.append(Vector3(float(x) * 0.12, 0.0, float(y) * 0.12))
	# Duplicate positions with different mesh indexes: both must weld to
	# precisely the same physics vertex during Jolt soft body construction.
	for i in range(GRID_VERTEX_COUNT):
		vertices.append(vertices[i])

	for y in range(GRID - 1):
		for x in range(GRID - 1):
			var a := y * GRID + x
			var b := a + 1
			var c := a + GRID
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b]))
			indices.append_array(PackedInt32Array([
				b + GRID_VERTEX_COUNT, c + GRID_VERTEX_COUNT, d + GRID_VERTEX_COUNT
			]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _exercise() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	var mesh := _build_cloth()
	var before_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var initial_usec := Time.get_ticks_usec()
	var largest_weld_error := 0.0
	var invalid_bounds := 0

	for wave in range(WAVES):
		var bodies: Array[RID] = []
		for body_index in range(BODIES_PER_WAVE):
			var body := PhysicsServer3D.soft_body_create()
			PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
			PhysicsServer3D.soft_body_set_collision_layer(body, 1)
			PhysicsServer3D.soft_body_set_collision_mask(body, 1)
			PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
			PhysicsServer3D.soft_body_set_space(body, space)
			bodies.append(body)

		for frame in range(2):
			await physics_frame

		for body in bodies:
			var p1 := PhysicsServer3D.soft_body_get_point_global_position(body, PROBE_INDEX)
			var p2 := PhysicsServer3D.soft_body_get_point_global_position(body, PROBE_INDEX + GRID_VERTEX_COUNT)
			largest_weld_error = maxf(largest_weld_error, p1.distance_to(p2))
			var bounds := PhysicsServer3D.soft_body_get_bounds(body)
			if bounds.size.length_squared() < 0.01:
				invalid_bounds += 1
			PhysicsServer3D.soft_body_set_space(body, RID())
			PhysicsServer3D.free_rid(body)

	var elapsed_ms := float(Time.get_ticks_usec() - initial_usec) / 1000.0
	var after_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"grid": GRID,
		"mesh_vertices": GRID_VERTEX_COUNT * 2,
		"triangles": (GRID - 1) * (GRID - 1) * 2,
		"soft_bodies_created": WAVES * BODIES_PER_WAVE,
		"construction_and_simulation_ms": elapsed_ms,
		"static_memory_growth_bytes": after_memory - before_memory,
		"max_duplicate_vertex_distance": largest_weld_error,
		"invalid_bounds": invalid_bounds
	}))
	if largest_weld_error > 0.0001 or invalid_bounds != 0:
		printerr("Jolt cloth vertex-index dedup regression failed")
		quit(1)
	else:
		print("Jolt soft-body vertex dedup regression passed.")
		quit(0)
