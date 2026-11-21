extends RefCounted
## Terrain / material / procgen editor panels (addons/cgame_terrain_tools, addons/cgame_procgen_tools), headless.

const TerrainPanel = preload("res://addons/cgame_terrain_tools/terrain_panel.gd")
const MaterialLayerPanel = preload("res://addons/cgame_terrain_tools/material_layer_panel.gd")
const ProcgenPanel = preload("res://addons/cgame_procgen_tools/procgen_panel.gd")
const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")


func _hilly(w: int, h: int) -> PackedFloat32Array:
	var hs := PackedFloat32Array()
	hs.resize(w * h)
	for y in h:
		for x in w:
			hs[y * w + x] = 10.0 + 8.0 * sin(float(x) * 0.3) * cos(float(y) * 0.25) + float(x) * 0.2
	return hs


func _max_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var m: float = 0.0
	for i in a.size():
		m = maxf(m, absf(a[i] - b[i]))
	return m


## V-shaped valley draining to the bottom edge, with an extra pit on one slope.
func _valley(w: int, h: int, pit: bool) -> Dictionary:
	var hs := PackedFloat32Array()
	hs.resize(w * h)
	for y in h:
		for x in w:
			hs[y * w + x] = absf(float(x) - float(w) * 0.5) * 0.8 + float(h - 1 - y) * 0.3 + 1.0
	if pit:
		hs[10 * w + 8] -= 3.0
	return ProcgenPanel.make_heightfield(hs, w, h, 1.0)


func run(t) -> void:
	t.current = "terrain panel strokes and layers"
	var base: PackedFloat32Array = _hilly(33, 33)
	var tp := TerrainPanel.new()
	tp.setup(33, 33, 16, base)
	t.eq(tp.layer_ids().size(), 0, "no layers at start")
	var pts := PackedVector2Array([Vector2(10, 10), Vector2(12, 10), Vector2(14, 10)])
	var n: int = tp.stroke(pts, {"kind": TerrainEditLayers.Brush.RAISE, "radius": 3.0, "strength": 2.0})
	t.check(n == 3, "all stroke points changed the layer")
	t.eq(tp.layer_ids().size(), 1, "stroke auto-created a layer")
	var raised: PackedFloat32Array = tp.heights()
	t.check(raised[10 * 33 + 12] > base[10 * 33 + 12] + 1.0, "stroke raised heights")
	t.near(raised[30 * 33 + 30], base[30 * 33 + 30], 0.0001, "far texels untouched")
	var lid: int = tp.layer_ids()[0]
	t.check(tp.edit.layer_delta_at(lid, 12, 10) > 1.0, "delta stored in the layer")
	tp.set_layer_visible(lid, false)
	t.check(_max_diff(tp.heights(), base) < 0.0001, "hiding the layer restores base")
	tp.set_layer_visible(lid, true)
	tp.set_layer_opacity(lid, 0.5)
	t.check(tp.heights()[10 * 33 + 12] < raised[10 * 33 + 12], "opacity scales the layer")
	tp.set_layer_opacity(lid, 1.0)
	var l2: int = tp.add_layer("second")
	var order: PackedInt32Array = tp.layer_ids()
	t.eq(order[1], l2, "new layer on top")
	t.check(tp.move_layer(l2, 0), "move layer")
	t.eq(tp.layer_ids()[0], l2, "layer moved to bottom")
	t.check(tp.remove_layer(l2), "remove layer")
	var img: Image = tp.preview_image()
	t.eq(img.get_width(), 33, "preview width")
	t.eq(img.get_height(), 33, "preview height")

	t.current = "terrain panel undo"
	t.check(tp.can_undo(), "can undo stroke")
	t.check(tp.undo(), "undo stroke")
	t.check(_max_diff(tp.heights(), base) < 0.0001, "undo restores heights")
	t.check(tp.redo(), "redo stroke")
	t.check(tp.heights()[10 * 33 + 12] > base[10 * 33 + 12] + 1.0, "redo reapplies stroke")
	tp.free()

	t.current = "terrain erosion layer"
	var ep := TerrainPanel.new()
	ep.setup(33, 33, 16, base)
	var rect := Rect2i(4, 4, 24, 24)
	var eid: int = ep.apply_erosion(rect, 2500, 5)
	t.check(eid >= 0, "erosion created a layer")
	t.eq(ep.layer_ids().size(), 1, "erosion lives in its own layer")
	var eroded: PackedFloat32Array = ep.heights()
	t.check(_max_diff(eroded, base) > 0.001, "erosion changed composite heights")
	t.near(eroded[0], base[0], 0.0001, "outside rect unchanged")
	ep.set_layer_visible(eid, false)
	t.check(_max_diff(ep.heights(), base) < 0.0001, "hiding erosion layer restores base")
	ep.set_layer_visible(eid, true)
	t.check(ep.undo(), "undo erosion")
	t.eq(ep.layer_ids().size(), 0, "undo removed erosion layer")
	t.check(_max_diff(ep.heights(), base) < 0.0001, "undo erosion restores heights")
	t.check(ep.redo(), "redo erosion")
	t.check(_max_diff(ep.heights(), eroded) < 0.0001, "redo erosion reproduces result")
	t.eq(ep.apply_erosion(Rect2i(0, 0, 2, 2), 10, 1), -1, "tiny rect rejected")
	ep.free()

	t.current = "material layer panel"
	var mp := MaterialLayerPanel.new()
	mp.add_layer("grass", Color(0.2, 0.6, 0.2))
	mp.add_layer("rock", Color(0.5, 0.5, 0.5), "slope")
	mp.add_layer("sand", Color(0.9, 0.8, 0.5), "noise")
	t.eq(mp.layer_count(), 3, "three layers")
	t.check(mp.move_layer(0, 2), "reorder")
	t.eq(mp.layer_names(), PackedStringArray(["rock", "sand", "grass"]), "order after move")
	t.check(mp.set_blend_mode(2, "height"), "set blend mode")
	t.check(not mp.set_blend_mode(2, "bogus"), "bad blend mode rejected")
	t.check(mp.set_blend_param(1, "scale", 2.5), "blend param")
	t.check(mp.set_param(1, "roughness", 0.3), "layer param")
	t.check(mp.remove_layer(2), "remove layer")
	mp.add_layer("mud", Color(0.3, 0.2, 0.1))
	var js: String = mp.export_json()
	t.check(js.contains("\"noise\"") and js.contains("\"rock\""), "json holds modes and names")
	var parsed: Variant = JSON.parse_string(js)
	t.check(parsed is Dictionary, "json parses")
	var mp2 := MaterialLayerPanel.new()
	t.check(mp2.import_json(js), "import json")
	t.eq(mp2.layer_names(), mp.layer_names(), "json round trip keeps order")
	t.check(not mp2.import_json("nope"), "bad json rejected")
	var code: String = mp.shader_code()
	t.check(code.contains("shader_type spatial") and code.length() > 200, "shader code generated")
	var mat: ShaderMaterial = mp.preview_material()
	t.check(mat != null and mat.shader != null and not mat.shader.code.is_empty(), "preview material has a shader")
	mp.free()
	mp2.free()

	t.current = "river network"
	var pg := ProcgenPanel.new()
	pg.river_sources = 6
	var vf: Dictionary = _valley(48, 48, true)
	var rivers: Array = pg.generate_rivers(11, vf, 6)
	t.check(rivers.size() >= 2, "several rivers generated")
	var merges: int = 0
	var downhill: bool = true
	var ends_at_edge: bool = true
	for r in rivers:
		var rd: Dictionary = r
		var levels: PackedFloat32Array = rd["levels"]
		for i in range(1, levels.size()):
			if levels[i] >= levels[i - 1]:
				downhill = false
		var cells: PackedInt32Array = rd["cells"]
		var last: int = cells[cells.size() - 1]
		@warning_ignore("integer_division")
		var ly: int = last / 48
		var lx: int = last - ly * 48
		if str(rd["merges_into"]) != "":
			merges += 1
		elif lx != 0 and ly != 0 and lx != 47 and ly != 47:
			ends_at_edge = false
	t.check(downhill, "rivers descend strictly on the filled surface")
	t.check(ends_at_edge, "unmerged rivers reach the map edge (pits filled)")
	t.check(merges >= 1, "tributaries merge into a tree")
	var filled: Dictionary = ProcgenPanel.fill_pits(vf["heights"], 48, 48)
	var fh: PackedFloat32Array = filled["filled"]
	var raw: PackedFloat32Array = vf["heights"]
	t.check(fh[10 * 48 + 8] > raw[10 * 48 + 8] + 1.0, "pit raised by filling")

	t.current = "road/river crossings"
	var road_list: Array = [{"id": "road_x", "points": PackedVector2Array([Vector2(0, 20), Vector2(47, 20)])}]
	var cross: Array = ProcgenPanel.find_crossings(road_list, rivers)
	t.check(cross.size() >= 1, "horizontal road crosses the valley river")
	var cross_ok: bool = true
	for c in cross:
		var cd: Dictionary = c
		var cp: Vector2 = cd["point"]
		if absf(cp.y - 20.0) > 0.01:
			cross_ok = false
	t.check(cross_ok, "crossing points lie on the road")
	var no_cross: Array = ProcgenPanel.find_crossings([{"id": "road_y", "points": PackedVector2Array([Vector2(-10, -10), Vector2(-5, -5)])}], rivers)
	t.eq(no_cross.size(), 0, "no crossing for a distant road")

	t.current = "generate_all and settlements"
	pg.river_sources = 3
	pg.site_count = 3
	pg.lots_per_settlement = 8
	pg.settlement_radius = 14.0
	var hf: Dictionary = ProcgenPanel.demo_heightfield(7, 96, 96)
	var res: Dictionary = pg.generate_all(3, hf)
	var sites: PackedVector2Array = res["sites"]
	t.check(sites.size() >= 2, "sites placed")
	var roads: Array = res["roads"]
	t.check(roads.size() >= sites.size() - 1, "road network connects all sites")
	var settlements: Array = res["settlements"]
	t.eq(settlements.size(), sites.size(), "settlement per site")
	var overlap: bool = false
	var total_lots: int = 0
	for s in settlements:
		var sd: Dictionary = s
		var lots: Array = sd["lots"]
		total_lots += lots.size()
		var plaza: Dictionary = sd["plaza"]
		var plaza_r: float = float(plaza["radius"])
		var plaza_c: Vector2 = plaza["center"]
		for i in lots.size():
			var a: Dictionary = lots[i]
			var ra: Rect2 = a["rect"]
			var ca: Vector2 = a["center"]
			if ca.distance_to(plaza_c) < plaza_r:
				overlap = true
			for j in range(i + 1, lots.size()):
				var b: Dictionary = lots[j]
				var rb: Rect2 = b["rect"]
				if ra.intersects(rb):
					overlap = true
	t.check(total_lots > 0, "lots generated")
	t.check(not overlap, "settlement lots do not overlap")
	var caves: Array = res["caves"]
	t.eq(caves.size(), 1, "one cave")
	var cave: Dictionary = caves[0]
	t.check(int(cave["open_cells"]) > 0 and int(cave["regions"]) == 1, "cave is open and connected")
	var cimg: Image = pg.preview_image(res, hf)
	t.eq(cimg.get_width(), 96, "procgen preview size")

	t.current = "export, overrides and determinism"
	var scene: Dictionary = pg.export_scene(res, hf)
	var nodes: Array = scene["nodes"]
	t.check(nodes.size() > 10, "scene has nodes")
	var first: Dictionary = nodes[0]
	t.check(first["transform"] is Transform3D and first.has("id") and first.has("type"), "node shape")
	var res2: Dictionary = pg.generate_all(3, hf)
	t.eq(hash(var_to_str(res2)), hash(var_to_str(res)), "same seed is deterministic")
	var res3: Dictionary = pg.generate_all(4, hf)
	t.check(hash(var_to_str(res3)) != hash(var_to_str(res)), "different seed differs")
	pg.set_override("lot_0_0", {"position": Vector3(5, 6, 7), "rotation_y": 1.0})
	pg.set_override("lot_0_1", {"deleted": true})
	for gen_seed in [3, 9]:
		var sc: Dictionary = pg.regenerate(gen_seed, hf)
		var found_lot: bool = false
		var found_deleted: bool = false
		for nn in sc["nodes"]:
			var nd: Dictionary = nn
			if str(nd["id"]) == "lot_0_0":
				var tr: Transform3D = nd["transform"]
				found_lot = tr.origin.is_equal_approx(Vector3(5, 6, 7)) and absf(tr.basis.get_euler().y - 1.0) < 0.001
			if str(nd["id"]) == "lot_0_1":
				found_deleted = true
		t.check(found_lot, "override kept after regeneration (seed %d)" % gen_seed)
		t.check(not found_deleted, "deleted override kept (seed %d)" % gen_seed)
	pg.clear_override("lot_0_1")
	t.check(not pg.overrides.has("lot_0_1"), "override cleared")
	pg.free()

	t.current = "panels headless lifecycle"
	var a1 := TerrainPanel.new()
	var a2 := MaterialLayerPanel.new()
	var a3 := ProcgenPanel.new()
	t.check(a1.get_child_count() > 0 and a2.get_child_count() > 0 and a3.get_child_count() > 0, "panels build their controls")
	a1.free()
	a2.free()
	a3.free()
	t.check(true, "panels freed")
