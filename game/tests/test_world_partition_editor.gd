extends RefCounted
## World Partition editor panel + biome painter + batch simplification.

const WPPanel = preload("res://addons/cgame_world_partition/world_partition_panel.gd")
const BiomePainter = preload("res://addons/cgame_world_partition/biome_painter.gd")


func _actor(pos: Vector3, layers: Array, guid: String = "") -> Dictionary:
	return {"guid": guid, "position": pos, "layers": PackedStringArray(layers), "spatially_loaded": true, "data": {}}


func run(t) -> void:
	var panel: Control = WPPanel.new()
	panel.size = Vector2(600, 400)
	var actors: Array = [
		_actor(Vector3(10, 0, 10), []),
		_actor(Vector3(20, 0, 20), []),
		_actor(Vector3(300, 0, 10), ["night"]),
		_actor(Vector3(10, 0, 300), ["night", "quest"], "fixed-guid"),
		{"guid": "", "position": Vector3(500, 0, 500), "spatially_loaded": false, "layers": PackedStringArray(), "data": {}},
	]
	panel.set_actors(actors)

	t.current = "guid assignment"
	var guids: Array = []
	for a in panel.get_actors():
		guids.append(a["guid"])
	t.check(not ("" in guids), "every actor has a guid")
	t.check("fixed-guid" in guids, "existing guid kept")
	var panel2: Control = WPPanel.new()
	panel2.set_actors(actors)
	var guids2: Array = []
	for a in panel2.get_actors():
		guids2.append(a["guid"])
	t.eq(guids, guids2, "guids stable across re-import")
	var dupes: Control = WPPanel.new()
	dupes.set_actors([_actor(Vector3.ONE, []), _actor(Vector3.ONE, [])])
	t.check(dupes.get_actors()[0]["guid"] != dupes.get_actors()[1]["guid"], "duplicates get distinct guids")
	dupes.free()
	panel2.free()

	t.current = "bake via panel"
	var baked: Dictionary = panel.bake(64.0)
	t.check(not baked.is_empty(), "bake returns data")
	t.eq(panel.get_cells().size(), 3, "three cells (default, night, night+quest)")
	t.eq(panel.always_loaded().size(), 1, "one always-loaded actor")
	t.check(panel.get_clusters().size() >= 1, "hlod clusters built")

	t.current = "cell selection"
	var origin: Vector2 = panel.world_to_local(Vector3(15, 0, 15))
	var key: String = panel.select_cell_at(origin)
	t.check(key != "", "cell found at actor position")
	t.eq(panel.actors_in_cell(key).size(), 2, "two actors in default cell")
	t.eq(panel.selected_cell, key, "selection stored")
	t.eq(panel.select_cell_at(Vector2(2, 2)), "", "empty space selects nothing")
	panel.size = Vector2(600, 400)

	t.current = "layer toggles change preview"
	var all: Array = panel.loaded_preview(Vector3(300, 0, 10), Vector3.ZERO)
	var night_key := ""
	for k in panel.get_cells():
		if (panel.get_cells()[k]["group"] as String) == "night":
			night_key = k
	t.check(night_key in all, "night cell streams in near source")
	panel.set_layer_enabled("night", false)
	t.check(not panel.is_layer_enabled("night"), "layer reports disabled")
	t.check(not (night_key in panel.loaded_preview(Vector3(300, 0, 10), Vector3.ZERO)), "disabled layer removed from preview")
	panel.set_layer_enabled("night", true)
	t.check(night_key in panel.loaded_preview(Vector3(300, 0, 10), Vector3.ZERO), "re-enabled layer returns")

	t.current = "layer assignment"
	var first_guid: String = guids[0]
	var changed: Array = panel.assign_layer([first_guid], "night")
	t.eq(changed.size(), 1, "one actor modified")
	t.check("night" in (changed[0]["layers"] as PackedStringArray), "layer added")
	t.eq(panel.assign_layer([first_guid], "night").size(), 0, "idempotent")
	t.eq(panel.remove_layer([first_guid], "night").size(), 1, "layer removed")
	t.eq(panel.remove_layer([first_guid], "night").size(), 0, "remove idempotent")

	t.current = "diff after move"
	panel.bake(64.0)
	panel.bake(64.0)
	t.eq((panel.diff_with_previous()["moved"] as Array).size(), 0, "no diff without changes")
	t.check(panel.move_actor(first_guid, Vector3(700, 0, 700)), "actor moved")
	panel.bake(64.0)
	var diff: Dictionary = panel.diff_with_previous()
	t.eq(diff["moved"], [first_guid], "moved actor detected")
	t.check((diff["dirty_cells"] as Array).size() >= 1, "dirty cells reported")

	t.current = "export ofpa"
	var dir: String = "user://wp_editor_test_ofpa"
	t.eq(panel.export_ofpa(dir), 5, "one file per actor")
	DirAccess.remove_absolute(dir)
	panel.free()

	t.current = "biome painter"
	var bp = BiomePainter.new()
	bp.setup(32, 32)
	t.near(bp.get_weight(5, 5, 0), 1.0, 0.0001, "starts as biome 0")
	var touched: int = bp.paint(Vector2(16, 16), 6.0, 2, 0.8)
	t.check(touched > 0, "brush touched texels")
	var normalised := true
	for y in 32:
		for x in 32:
			var s: float = 0.0
			for b in 4:
				s += bp.get_weight(x, y, b)
			if absf(s - 1.0) > 0.0001:
				normalised = false
	t.check(normalised, "weights normalised everywhere")
	t.check(bp.get_weight(16, 16, 2) > 0.5, "centre favours painted biome")
	t.near(bp.get_weight(0, 0, 2), 0.0, 0.0001, "outside brush untouched")
	var img: Image = bp.to_image()
	t.eq(img.get_width(), 32, "image width")
	t.eq(img.get_format(), Image.FORMAT_RGBA8, "image rgba8")
	t.check(img.get_pixel(16, 16).b > 0.5, "blue channel = biome 2")
	t.check(bp.undo(), "undo succeeds")
	t.near(bp.get_weight(16, 16, 2), 0.0, 0.0001, "undo restores")
	t.check(not bp.undo(), "nothing more to undo")

	t.current = "batch simplify"
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24
	var meshes: Array[Mesh] = [sphere]
	var ratios: Array[float] = [0.5, 0.1]
	var res: Array = bp.batch_simplify(meshes, ratios)
	t.eq(res.size(), 2, "one result per ratio")
	var src_tris: int = int(res[0]["source_tris"])
	t.check(src_tris > 1000, "source is dense")
	for r in res:
		t.check(int(r["tris"]) < src_tris and int(r["tris"]) > 0, "ratio %.2f reduces triangles (%d -> %d, %s)" % [r["ratio"], src_tris, r["tris"], r["method"]])
	t.check(int(res[1]["tris"]) <= int(res[0]["tris"]), "lower ratio not larger")
