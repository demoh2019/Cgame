extends RefCounted
## Regression: non-destructive terrain authoring really updates the running
## ChunkedTerrain3D height samples, without replacing the full source grid.

const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")
const TerrainEditBridge = preload("res://scripts/client/terrain_edit_bridge.gd")
const TerrainPanel = preload("res://addons/cgame_terrain_tools/terrain_panel.gd")
const TerrainPlugin = preload("res://addons/cgame_terrain_tools/plugin.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func _base(width: int, height: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(width * height)
	heights.fill(0.25)
	return heights


func run(t) -> void:
	t.current = "Terrain edit layers flush changed patches to the native terrain"
	var heights: PackedFloat32Array = _base(65, 65)
	var terrain := ChunkedTerrain3D.new()
	terrain.size = Vector2(64.0, 64.0)
	terrain.height_scale = 10.0
	terrain.chunk_quads = 16
	terrain.set_height_data(heights, Vector2i(65, 65))
	var edit := TerrainEditLayers.new()
	edit.setup(65, 65, 16, heights)
	edit.take_dirty_chunks() # Same base as the native terrain: no initial edit.
	var layer_id: int = edit.add_layer("Reclaim the road")
	var modified: Rect2i = edit.apply_brush(layer_id, TerrainEditLayers.Brush.RAISE,
		Vector2(8.0, 8.0), 2.0, 0.2, TerrainEditLayers.Falloff.CONSTANT)
	t.check(modified.size.x > 0, "existing non-destructive brush creates an actual edited region")
	var response: Dictionary = TerrainEditBridge.flush_dirty(edit, terrain)
	t.check(bool(response.get("ok", false)), "native region patch accepts the authored terrain")
	t.eq(int(response.get("applied", 0)), 1, "one local brush streams exactly one dirty edit cell")
	t.near(terrain.get_height_data()[8 * 65 + 8], 0.45, 0.00001,
		"terrain heights now reflect the visible sculpt layer")
	t.near(terrain.get_height_data()[40 * 65 + 40], 0.25, 0.00001,
		"unchanged far chunks retain their original terrain heights")
	t.eq(int(TerrainEditBridge.flush_dirty(edit, terrain)["applied"]), 0,
		"no dirty regions means no GPU/physics cache invalidation")

	t.current = "Terrain undo and custom normals propagate through the same sparse API"
	t.check(edit.undo(), "sculpt supports existing undo system")
	var undo_result: Dictionary = TerrainEditBridge.flush_dirty(edit, terrain)
	t.check(bool(undo_result.get("ok", false)), "reverting a stroke streams the restored heights")
	t.near(terrain.get_height_data()[8 * 65 + 8], 0.25, 0.00001,
		"undo restores the original native sample")
	var normals := PackedVector3Array()
	normals.resize(65 * 65)
	normals.fill(Vector3.UP)
	terrain.set_normal_data(normals)
	var id2: int = edit.add_layer("Slope")
	edit.apply_brush(id2, TerrainEditLayers.Brush.RAISE,
		Vector2(24.0, 24.0), 2.0, 0.15, TerrainEditLayers.Falloff.CONSTANT)
	var normal_result: Dictionary = TerrainEditBridge.flush_dirty(edit, terrain)
	t.check(bool(normal_result.get("ok", false)), "custom-normal height edits supply consistent region normals")
	t.eq(terrain.get_normal_data().size(), 65 * 65, "custom-normal grid stays allocated")
	t.check(terrain.get_normal_data()[24 * 65 + 23].is_finite(),
		"affected normals are regenerated and remain finite")

	t.current = "Terrain editor selection binds strokes and layer operations to the game renderer"
	var panel := TerrainPanel.new()
	t.check(panel.attach_terrain(terrain), "editor binds a selected real ChunkedTerrain3D node")
	t.check(panel.live_target == terrain, "live changes target that same existing render node")
	var before: float = terrain.get_height_data()[12 * 65 + 12]
	var updated: int = panel.stroke(PackedVector2Array([Vector2(12.0, 12.0)]),
		{"kind": TerrainEditLayers.Brush.RAISE, "radius": 2.0,
		"strength": 0.12, "falloff": TerrainEditLayers.Falloff.CONSTANT})
	t.eq(updated, 1, "terrain dock applies one edit stroke")
	t.check(terrain.get_height_data()[12 * 65 + 12] > before,
		"signal automatically commits authored heights into the actual terrain")
	t.check(panel.undo(), "editor undo is available")
	t.near(terrain.get_height_data()[12 * 65 + 12], before, 0.00001,
		"editor undo automatically patches the runtime terrain too")
	var source: String = (ChunkView as Script).source_code
	t.check(source.contains("_terrain.apply_color_patch(Rect2i(0, 0, SAMPLES, SAMPLES), colors)"),
		"the real game terrain uses native color-only patch updates during graphics changes")
	var plugin_source: String = (TerrainPlugin as Script).source_code
	t.check(plugin_source.contains("_forward_3d_gui_input") and \
		plugin_source.contains("terrain_panel.viewport_sculpt_enabled"),
		"explicit 3D viewport sculpt input reaches the bound terrain editor")
	panel.free()
	terrain.free()

	t.current = "Large authoring chunks split into bounded native patch transactions"
	var big_heights: PackedFloat32Array = _base(129, 129)
	var big_native := ChunkedTerrain3D.new()
	big_native.set_height_data(big_heights, Vector2i(129, 129))
	var big_edit := TerrainEditLayers.new()
	big_edit.setup(129, 129, 128, big_heights)
	big_edit.take_dirty_chunks()
	var big_layer: int = big_edit.add_layer("Mountain")
	big_edit.apply_brush(big_layer, TerrainEditLayers.Brush.RAISE,
		Vector2(64.0, 64.0), 2.0, 0.2, TerrainEditLayers.Falloff.CONSTANT)
	var big_result: Dictionary = TerrainEditBridge.flush_dirty(big_edit, big_native)
	t.check(bool(big_result.get("ok", false)), "128-quad terrain tiles split into native-safe edits")
	t.check(int(big_result.get("applied", 0)) > 1,
		"large dirty region is decomposed into multiple bounded patch submissions")
	t.near(big_native.get_height_data()[64 * 129 + 64], 0.45, 0.00001,
		"large-chunk paint still reaches the real native height grid")
	big_native.free()

	t.current = "Bad target dimensions cannot silently drop authoring edits"
	var wrong := ChunkedTerrain3D.new()
	wrong.set_height_data(_base(17, 17), Vector2i(17, 17))
	edit.apply_brush(id2, TerrainEditLayers.Brush.RAISE, Vector2(24.0, 24.0), 2.0, 0.1)
	t.eq(str(TerrainEditBridge.flush_dirty(edit, wrong)["reason"]), "dimensions_mismatch",
		"editor detects incorrect dimensions before consuming pending work")
	t.check(edit.take_dirty_chunks().size() > 0,
		"failed target validation keeps dirty edits available to retry")
	wrong.free()
