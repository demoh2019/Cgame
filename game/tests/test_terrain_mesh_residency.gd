extends RefCounted
## The live terrain renderer must evict unused GPU mesh RIDs after LOD changes,
## not just limit how many LODs it builds per frame.
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "native GPU terrain mesh cache API and safe defaults"
	var terrain := ChunkedTerrain3D.new()
	# Installed game builds can temporarily lag behind their C++ source.
	# Gameplay must still create chunks and change graphics presets safely.
	var code: String = (ChunkView as Script).source_code
	t.check(code.contains("terrain.has_method(\"set_max_cached_lods\")"),
		"residency configuration checks the engine API before using it")
	t.check(code.contains("_set_terrain_mesh_residency(_terrain)"),
		"new terrain chunks share the same compatibility-aware setter")
	if not terrain.has_method("set_max_cached_lods"):
		terrain.add_to_group(ChunkView.TERRAIN_LOD_GROUP)
		ChunkView.configure_terrain_mesh_residency(3)
		ChunkView.apply_terrain_mesh_residency(terrain)
		ChunkView.apply_terrain_error_lod(terrain)
		ChunkView.apply_terrain_geomorph(terrain)
		t.check(not terrain.has_method("set_max_cached_lods"),
			"older terrain binaries skip GPU cache tuning without crashing")
		terrain.free()
		ChunkView.configure_terrain_mesh_residency(1)
		return
	t.eq(terrain.max_cached_lods, 0, "existing engine scenes retain unlimited legacy cache")
	t.eq(terrain.get_cached_mesh_count(), 0, "empty terrain has no resident GPU meshes")
	terrain.max_cached_lods = -8
	t.eq(terrain.max_cached_lods, 0, "negative cache cap falls back to unlimited")
	terrain.max_cached_lods = 999
	t.eq(terrain.max_cached_lods, 8, "cache cap cannot exceed native LOD array size")
	terrain.max_cached_lods = 2
	t.eq(terrain.max_cached_lods, 2, "per-chunk residency cap is configurable")
	terrain.free()

	t.current = "graphics quality controls active terrain residency"
	var caps := [1, 2, 2, 3]
	for quality in 4:
		ChunkView.configure_terrain_mesh_residency(quality)
		t.eq(ChunkView.terrain_max_cached_lods, caps[quality],
			"graphic preset selects deterministic per-chunk GPU residency budget")
		var node := ChunkedTerrain3D.new()
		node.add_to_group(ChunkView.TERRAIN_LOD_GROUP)
		ChunkView.apply_terrain_mesh_residency(node)
		t.eq(node.max_cached_lods, caps[quality],
			"runtime GPU cache cap is applied to active terrain nodes")
		node.free()
	t.check((ChunkView as Script).source_code.contains(
		"_set_terrain_mesh_residency(_terrain)"),
		"new gameplay terrain gets a GPU cache budget when the executable supports it")
	t.check((GraphicsQuality as Script).source_code.contains(
		"ChunkView.apply_terrain_mesh_residency(lod_terrain)"),
		"quality changes retune already resident world chunks without rebuilding heightmaps")

	t.current = "LOD mesh residency survives camera travel and budget reductions"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		t.check(false, "the headless test SceneTree is available")
		return
	var holder := Node3D.new()
	holder.name = "TerrainResidencyFixture"
	var eye := Node3D.new()
	eye.name = "Eye"
	holder.add_child(eye)
	var live := ChunkedTerrain3D.new()
	live.name = "Terrain"
	live.centered = false
	live.size = Vector2(32, 32)
	live.chunk_quads = 8
	live.lod_count = 3
	live.lod_distance = 16.0
	live.collision_enabled = false
	live.max_cached_lods = 2
	live.focus = NodePath("../Eye")
	var heights := PackedFloat32Array()
	heights.resize(17 * 17)
	for z in 17:
		for x in 17:
			heights[z * 17 + x] = 0.2 + 0.1 * sin(float(x) * 0.32) * cos(float(z) * 0.22)
	live.set_height_data(heights, Vector2i(17, 17))
	holder.add_child(live)
	tree.root.add_child(holder)
	eye.position = Vector3(2, 1, 2)
	live.force_update()
	var chunks: int = live.get_chunk_count()
	var near_count: int = live.get_cached_mesh_count()
	t.check(chunks >= 4 and near_count > 0, "nearby terrain creates resident geometry")
	t.check(near_count <= chunks * 2, "each active terrain chunk respects two LOD meshes")
	eye.position = Vector3(30, 1, 30)
	live.force_update()
	t.check(live.get_cached_mesh_count() <= chunks * 2,
		"camera movement does not accumulate an unbounded number of mesh RIDs")
	eye.position = Vector3(900, 1, 900)
	live.force_update()
	t.check(live.get_cached_mesh_count() <= chunks * 2,
		"far LOD remains resident without exceeding the two-mesh cap")
	live.max_cached_lods = 1
	t.check(live.get_cached_mesh_count() <= chunks,
		"reducing the cap evicts unused GPU mesh RIDs immediately")
	for z in live.get_chunk_grid_size().y:
		for x in live.get_chunk_grid_size().x:
			var cell := Vector2i(x, z)
			var kept: int = live.get_chunk_cached_lod_count(cell)
			t.check(kept <= 1,
				"one active LOD is kept for every terrain chunk after live eviction")
			if live.get_chunk_lod(cell) >= 0:
				t.eq(kept, 1,
					"LRU eviction never frees the currently rendered mesh RID")
	eye.position = Vector3(2, 1, 2)
	live.force_update()
	t.check(live.get_cached_mesh_count() > 0 and live.get_cached_mesh_count() <= chunks,
		"walking back rebuilds the required LOD while retaining the residency cap")
	t.eq(live.collision_enabled, false,
		"GPU eviction does not enable client-side authoritative collision")
	holder.queue_free()
	ChunkView.configure_terrain_mesh_residency(1)
