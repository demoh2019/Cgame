extends RefCounted
## P1 Unreal Landscape component-style native partial height edits, exercised
## on the actual ChunkedTerrain3D that streamed Albion scenes already use.
const TerrainLivePatch = preload("res://scripts/client/terrain_live_patch.gd")
const OnlineMain = preload("res://scripts/client/online_main.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "game terrain editing is wired into the actual streamed chunk renderer"
	var source: String = (OnlineMain as Script).source_code
	var chunks: String = (ChunkView as Script).source_code
	t.check(source.contains('TerrainLivePatch.apply_to_streamed_world('),
		"real Albion online client invokes the patch tool")
	t.check(source.contains("OS.is_debug_build()") and
		source.contains("event.ctrl_pressed and event.shift_pressed") and
		source.contains("event.keycode == KEY_F9"),
		"terrain sculpt is explicitly debug-only and cannot consume normal F9")
	t.check(chunks.contains("_terrain = ChunkedTerrain3D.new()") and
		chunks.contains("_terrain.add_to_group(TERRAIN_LOD_GROUP)"),
		"patch tool edits the existing fully integrated streamed terrain")
	t.check(chunks.contains("_terrain.collision_enabled = false"),
		"gameplay physics and server terrain authority are not changed")

	t.current = "native partial landscape edit validates and updates only one area"
	if not ClassDB.class_exists("ChunkedTerrain3D"):
		t.check(true, "stock Godot does not provide Cgame chunked terrain")
		return
	var terrain: Node3D = ClassDB.instantiate("ChunkedTerrain3D") as Node3D
	t.check(terrain != null, "native terrain class instantiated")
	if terrain == null:
		return
	if not terrain.has_method("apply_height_patch"):
		t.check(true, "older Cgame remains supported without runtime sculpt API")
		terrain.free()
		return
	terrain.set("centered", false)
	terrain.set("size", Vector2(64, 64))
	terrain.set("height_scale", 10.0)
	terrain.set("chunk_quads", 32)
	terrain.set("collision_enabled", false)
	var base := PackedFloat32Array()
	base.resize(65 * 65)
	base.fill(0.5)
	terrain.call("set_height_data", base, Vector2i(65, 65))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(terrain)
	terrain.add_to_group("aa_chunked_terrain_lod")
	terrain.call("force_update")
	t.eq(int(terrain.call("get_chunk_count")), 4,
		"the test uses four real chunks with independent cached mesh/LOD")
	var far_error: float = float(terrain.call("get_chunk_lod_error", Vector2i(1, 1), 1))
	t.near(far_error, 0.0, 0.00001,
		"all distant untouched terrain tiles start perfectly flat")
	t.check(TerrainLivePatch.apply_visual_brush(terrain, Vector3(7, 0, 7), 2.0, 0.75),
		"native terrain patch handles live cosmetic sculpting")
	var changed: PackedFloat32Array = terrain.call("get_height_data")
	t.check(changed[7 * 65 + 7] > 0.5,
		"the real native heightfield changed at the sculpted center")
	t.eq(changed[20 * 65 + 20], 0.5,
		"only the specified dirty patch was edited")
	t.eq(int(terrain.call("get_chunk_count")), 4,
		"partial edit does not recreate all terrain chunk structures")
	t.near(float(terrain.call("get_chunk_lod_error", Vector2i(1, 1), 1)),
		far_error, 0.00001, "far chunk LOD error is not invalidated")
	t.check(float(terrain.call("get_chunk_lod_error", Vector2i(0, 0), 1)) > 0.01,
		"edited chunk recalculates its coarse mesh error")
	t.eq(int(terrain.call("get_collision_chunk_count")), 0,
		"cosmetic terrain editing does not create client-side collision")
	t.check(not bool(terrain.call("apply_height_patch", Rect2i(1, 1, 2, 2),
		PackedFloat32Array([0.3, 0.4, NAN, 0.6]))),
		"invalid late sample rejects entire native edit")
	t.eq(terrain.call("get_height_data"), changed,
		"rejected patch preserves all already existing heights")
	t.check(not TerrainLivePatch.apply_visual_brush(
		terrain, Vector3(7, 0, 7), NAN, 1.0),
		"invalid brush radius cannot corrupt terrain")

	t.current = "real scene-tree group routing picks the streamed terrain tile"
	t.check(TerrainLivePatch.apply_to_streamed_world(tree, Vector3(7, 0, 7)),
		"group-based debug hotkey route edits an existing chunk instance")
	t.check(not TerrainLivePatch.apply_to_streamed_world(tree, Vector3(1000, 0, 1000)),
		"sculpting outside loaded terrain creates no hidden new terrain")
	terrain.free()
