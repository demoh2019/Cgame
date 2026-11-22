extends RefCounted
## Terrain runtime virtual texture: page layout, chunk binding, page-table encoding, eviction, shader wiring.
const TerrainRvt = preload("res://scripts/client/terrain_rvt.gd")


func run(t) -> void:
	t.current = "pages around the camera, nearest first"
	var rvt = TerrainRvt.new()
	var radii: Array[float] = [26.0, 66.0]
	rvt.level_radius = radii
	var rows: Array = rvt._wanted_pages(Vector3(100.0, 30.0, 100.0))
	t.check(not rows.is_empty() and rows.size() <= TerrainRvt.CAPACITY, "page set fits the cache")
	var ordered := true
	var levels := {0: 0, 1: 0}
	for i in rows.size():
		levels[rows[i][1].x] += 1
		if i > 0 and float(rows[i][0]) < float(rows[i - 1][0]):
			ordered = false
	t.check(ordered, "closest pages are baked first")
	t.check(levels[0] > 0 and levels[1] > levels[0], "fine level near, coarse level further out")
	var page: Vector3i = rows[0][1]
	t.eq(page.x, 0, "the page under the camera is level 0")
	t.eq(page, Vector3i(0, 12, 12), "8 m pages: x 100 m is page 12")

	t.current = "pages never straddle chunks and map to their chunk"
	t.eq(rvt._chunk_of(Vector3i(0, 7, -1)), Vector2i(0, -1), "8 m page 7 lies in chunk 0, page -1 in chunk -1")
	t.eq(rvt._chunk_of(Vector3i(1, 4, 3)), Vector2i(1, 0), "16 m page 4 starts chunk 1")
	t.check(int(64.0) % int(TerrainRvt.LEVEL_PAGE[1]) == 0 and int(64.0) % int(TerrainRvt.LEVEL_PAGE[0]) == 0,
		"64 m chunks hold whole pages of both levels")

	t.current = "toroidal page table encoding matches the shader"
	rvt._table_image = Image.create(TerrainRvt.TABLE * 2, TerrainRvt.TABLE, false, Image.FORMAT_RGBA8)
	rvt._layer_keys.resize(TerrainRvt.CAPACITY)
	var key := Vector3i(1, -3, 37)
	rvt._pages[key] = 129
	rvt._write_table(key, 129)
	var slot: Vector2i = rvt._slot(key)
	t.eq(slot, Vector2i((-3 & 31) + 32, 37 & 31), "level 1 uses the right half, negative pages wrap")
	var texel: Color = rvt._table_image.get_pixelv(slot)
	var layer: int = roundi(texel.r * 255.0) + roundi(texel.g * 255.0) * 256 - 1
	t.eq(layer, 129, "layer + 1 stored in r/g")
	t.eq(roundi(texel.b * 255.0), -3 & 255, "page x check byte")
	t.eq(roundi(texel.a * 255.0), 37 & 255, "page z check byte")

	t.current = "eviction frees the layer and clears only its own slot"
	var other := Vector3i(1, 29, 37) # Same toroidal slot (29 = -3 + 32), different page.
	rvt._release(other)
	t.check(rvt._table_image.get_pixelv(slot).a > 0.0, "a different page cannot clear this slot")
	rvt._release(key)
	t.check(not rvt._pages.has(key) and rvt._free.has(129), "layer back in the free list")
	t.eq(rvt._table_image.get_pixelv(slot), Color(0, 0, 0, 0), "slot cleared")

	t.current = "terrain and shader wiring"
	t.eq(TerrainRvt.terrain_layers() & 1, 1, "terrain stays on the default layer for game cameras")
	t.check(TerrainRvt.terrain_layers() & TerrainRvt.TERRAIN_LAYER != 0, "and on the bake layer")
	var shader: String = FileAccess.get_file_as_string("res://assets/shaders/ground.gdshader")
	t.check(shader.contains("AA_RVT_BAKE_ALBEDO = %du" % TerrainRvt.MARK_ALBEDO)
		and shader.contains("AA_RVT_BAKE_DATA = %du" % TerrainRvt.MARK_DATA)
		and shader.contains("AA_RVT_BAKE_WET = %du" % TerrainRvt.MARK_WET), "marker layers agree with the shader")
	t.check(shader.contains("AA_RVT_TEXELS = %d.0" % TerrainRvt.PAGE_TEXELS), "page size agrees with the shader")
	var chunk: String = FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(chunk.contains("_terrain.render_layers = TerrainRvt.terrain_layers()"), "chunks join the bake layer")
	rvt.free()
