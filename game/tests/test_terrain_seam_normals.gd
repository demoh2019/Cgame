extends RefCounted
## Requires the forked ChunkedTerrain3D custom normal source; no GPU is needed.

const SeamNormals = preload("res://scripts/client/terrain_seam_normals.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")

static func _height(x: float, z: float) -> float:
	return 0.002 * x * x + 0.012 * z + 4.0


static func _grid(origin: Vector2, count: int, step: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	for z in count:
		for x in count:
			heights.append(_height(origin.x + x * step, origin.y + z * step))
	return heights


func run(t) -> void:
	t.current = "seamless terrain normal field"
	var size := 33
	var step := 2.0
	var start := Vector2(-64.0, 10.0)
	var next := start + Vector2(64.0, 0.0)
	var left := SeamNormals.build(_grid(start, size, step), start, size, step,
		-45.0, 220.0, Callable(self, "_height"))
	var right := SeamNormals.build(_grid(next, size, step), next, size, step,
		-45.0, 220.0, Callable(self, "_height"))
	t.eq(left.size(), size * size, "left chunk has one normal per height sample")
	t.eq(right.size(), size * size, "right chunk has one normal per height sample")
	for z in size:
		t.check(left[z * size + size - 1].is_equal_approx(right[z * size]),
			"adjacent chunks compute identical border normals at row %d" % z)
	t.check(left[0].y > 0.0 and left[0].is_normalized(),
		"normals stay unit length and point upward")
	t.check(not left[size - 1].is_equal_approx(left[0]),
		"varying terrain slope produces physically different normals")
	t.eq(SeamNormals.build(PackedFloat32Array(), start, size, step,
		-45.0, 220.0, Callable(self, "_height")).size(), 0,
		"invalid input never produces a misaligned normal buffer")

	t.current = "engine terrain uses normal overrides"
	var terrain := ChunkedTerrain3D.new()
	var normalized := PackedFloat32Array()
	for h in _grid(start, size, step):
		normalized.append((h + 45.0) / 220.0)
	terrain.centered = false
	terrain.size = Vector2(64, 64)
	terrain.height_scale = 220.0
	terrain.height_offset = -45.0
	terrain.set_height_data(normalized, Vector2i(size, size))
	terrain.set_normal_data(left)
	t.eq(terrain.get_normal_data().size(), size * size,
		"forked engine stores one custom normal for every source vertex")
	var midpoint: Vector3 = terrain.get_normal_data()[16 * size + 16]
	t.check(midpoint.is_equal_approx(left[16 * size + 16]),
		"engine normal override retains source-grid tangent direction")
	terrain.set_height_data(normalized, Vector2i(size, size))
	t.eq(terrain.get_normal_data().size(), 0,
		"replacing height data invalidates old normal information")
	terrain.free()
	var chunk_script: GDScript = load("res://scripts/client/chunk_view.gd") as GDScript
	t.check(chunk_script != null and chunk_script.source_code.contains(
		"_terrain.set_normal_data(TerrainSeamNormals.build("),
		"streamed world terrain passes seam normals into custom engine")
