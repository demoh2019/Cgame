extends RefCounted
## Fracture / cloth / hair authoring tools (addons/cgame_sim_authoring).

const FractureTool = preload("res://addons/cgame_sim_authoring/fracture_tool.gd")
const ClothTool = preload("res://addons/cgame_sim_authoring/cloth_tool.gd")
const HairGroomTool = preload("res://addons/cgame_sim_authoring/hair_groom_tool.gd")
const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")
const HairStrands = preload("res://scripts/client/hair_strands.gd")
const XPBDCloth = preload("res://scripts/shared/xpbd_cloth.gd")


func _make_hair() -> RefCounted:
	var h: RefCounted = HairStrands.new()
	var roots := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in 5:
		roots.append(Vector3(float(i) * 0.2, 0.0, 0.0))
		normals.append(Vector3.DOWN)
	h.call("grow_guides", roots, normals, 4, 0.4)
	return h


func _tip_spread(h: RefCounted) -> float:
	var ppg: int = h.get("points_per_guide")
	var rest: PackedVector3Array = h.get("rest")
	var lo := rest[ppg - 1]
	var hi := rest[ppg - 1]
	for g in (h.get("guide_count") as int):
		lo = lo.min(rest[g * ppg + ppg - 1])
		hi = hi.max(rest[g * ppg + ppg - 1])
	return (hi - lo).length()


func run(t) -> void:
	var size := Vector3(2, 2, 2)
	t.current = "fracture preview"
	var ft := FractureTool.new()
	var cells: Array = ft.preview(size, 8, 3)
	t.eq(cells.size(), 8, "one cell per piece")
	var vol := 0.0
	for c in cells:
		vol += VoronoiFracture.cell_volume(c as PackedVector3Array)
	t.near(vol, 8.0, 0.2, "cell volumes fill the box")

	t.current = "explode view"
	var xf: Array = ft.explode_view(cells, 1.5)
	t.eq(xf.size(), cells.size(), "one transform per cell")
	var outward := true
	for i in cells.size():
		var c: Vector3 = VoronoiFracture.centroid(cells[i] as PackedVector3Array)
		var o: Vector3 = (xf[i] as Transform3D).origin
		if c.length() > 0.01 and o.dot(c) <= 0.0:
			outward = false
		t.near(o.length(), c.length() * 1.5, 0.001, "offset scales with factor")
	t.check(outward, "offsets point away from centre")

	t.current = "fracture levels"
	var lv: Array = ft.levels(size, PackedInt32Array([2, 8, 4]), 5)
	t.eq(lv.size(), 3, "three levels")
	t.eq((lv[0] as Dictionary)["count"] as int, 8, "finest first")
	t.eq((lv[1] as Dictionary)["count"] as int, 4, "middle level")
	t.eq((lv[2] as Dictionary)["count"] as int, 2, "coarsest level")
	for l in lv:
		var d: Dictionary = l
		var seen := PackedInt32Array()
		seen.resize(8)
		for m in (d["members"] as Array):
			t.check((m as PackedInt32Array).size() > 0, "no empty parent")
			for idx in (m as PackedInt32Array):
				seen[idx] += 1
		var once := true
		for v in seen:
			if v != 1:
				once = false
		t.check(once, "parents cover every fragment exactly once")

	t.current = "fracture asset"
	for ext in ["json", "bin"]:
		var path := "user://sim_authoring_test.%s" % ext
		var data := {"size": size, "cells": cells, "n": 8}
		t.check(ft.save_asset(path, data), "saved " + ext)
		var back: Dictionary = ft.load_asset(path)
		t.eq(back.get("n", -1) as int, 8, "int round trip " + ext)
		var bc: Array = back.get("cells", []) as Array
		t.eq(bc.size(), cells.size(), "cell count round trip " + ext)
		if bc.size() == cells.size():
			var a: PackedVector3Array = cells[3]
			var b: PackedVector3Array = bc[3]
			t.eq(b.size(), a.size(), "point count " + ext)
			if a.size() == b.size() and a.size() > 0:
				t.near(a[0].x, b[0].x, 0.0001, "point value " + ext)
		DirAccess.remove_absolute(path)
		t.check(not FileAccess.file_exists(path), "asset deleted " + ext)
	t.check(ft.load_asset("user://sim_missing.json").is_empty(), "missing asset is empty")

	t.current = "cloth pins and maps"
	var ct := ClothTool.new()
	var cloth: RefCounted = XPBDCloth.new()
	cloth.call("setup_grid", 6, 6, 0.1, Transform3D.IDENTITY)
	var hit: PackedInt32Array = ct.paint_pins(cloth, Vector3(0, 0, 0), 0.15, true)
	t.check(hit.size() > 0, "pins painted")
	var pts: PackedVector3Array = cloth.call("positions")
	var radius_ok := true
	for i in pts.size():
		var inside: bool = pts[i].distance_to(Vector3.ZERO) <= 0.15
		if inside != (cloth.call("is_pinned", i) as bool):
			radius_ok = false
	t.check(radius_ok, "pinned exactly inside radius")
	ct.paint_pins(cloth, Vector3.ZERO, 0.15, false)
	t.check(not (cloth.call("is_pinned", 0) as bool), "unpaint releases pins")
	var painted: int = ct.paint_mass(cloth, Vector3(0.5, -0.5, 0), 0.2, 4.0)
	t.check(painted > 0, "mass painted")
	var inv: PackedFloat32Array = cloth.get("_base_inv_mass")
	var k: int = cloth.call("index_of", 5, 5)
	t.check(inv[k] < 1.0, "heavier particle has lower inverse mass")
	t.check(ct.paint_compliance(cloth, Vector3.ZERO, 0.3, 0.5) > 0, "compliance painted")
	t.check(ct.apply_compliance_map(cloth) > 0.02, "compliance map applied")

	t.current = "cloth skeleton binding"
	var bones := {"hip": Vector3(0.25, -0.5, 0), "chest": Vector3(0.25, 0.0, 0), "tip": Vector3(0.5, -0.5, 0)}
	var cl2: RefCounted = XPBDCloth.new()
	cl2.call("setup_grid", 5, 5, 0.1, Transform3D.IDENTITY)
	var map: Dictionary = ct.auto_attach_to_skeleton(cl2, bones, 0.2)
	var p2: PackedVector3Array = cl2.call("positions")
	t.eq(map.size(), p2.size(), "every particle mapped")
	var nearest_ok := true
	for i in p2.size():
		var best := ""
		var bd := INF
		for b in bones:
			var d: float = p2[i].distance_to(bones[b] as Vector3)
			if d < bd:
				bd = d
				best = b as String
		if map[i] != best:
			nearest_ok = false
	t.check(nearest_ok, "mapped to nearest bone")
	var att: PackedInt32Array = ct.pin_near_bones(cl2, map, bones, 0.2)
	t.check(att.size() > 0 and (cl2.call("is_pinned", att[0]) as bool), "particles near bones attached")

	t.current = "cloth presets"
	for pn in ["cape", "flag", "skirt"]:
		var cfg: Dictionary = ct.preset(pn)
		t.check(not cfg.is_empty(), pn + " preset exists")
		t.check((cfg["width_cells"] as int) > 0 and (cfg["spacing"] as float) > 0.0 and (cfg["mass"] as float) > 0.0, pn + " sane")
		var built: RefCounted = ct.build_from_preset(pn)
		t.check(built != null and (built.call("particle_count") as int) == ((cfg["width_cells"] as int) + 1) * ((cfg["height_cells"] as int) + 1), pn + " builds")
		var pinned := 0
		for i in (built.call("particle_count") as int):
			if built.call("is_pinned", i):
				pinned += 1
		t.check(pinned > 0, pn + " has pins")
		built.call("step", 1.0 / 60.0, 4)
		t.check((built.call("max_stretch_error") as float) < 0.5, pn + " steps stable")
	t.check(ct.preset("nope").is_empty(), "unknown preset empty")
	var dc: RefCounted = XPBDCloth.new()
	dc.call("setup_grid", 3, 3, 0.1, Transform3D.IDENTITY)
	dc.call("set_particle", 5, Vector3(0.3, -0.1, 0.0))
	ct.bake_rest_pose(dc)
	t.check((dc.call("max_stretch_error") as float) < 0.0001, "bake_rest_pose zeroes stretch error")

	t.current = "hair comb"
	var gt := HairGroomTool.new()
	var hair := _make_hair()
	var before: PackedVector3Array = (hair.get("rest") as PackedVector3Array).duplicate()
	var n: int = gt.comb(hair, Vector3(0.0, -0.2, 0.0), 0.15, Vector3.RIGHT, 1.0)
	t.check(n >= 1, "comb touches guides")
	var after: PackedVector3Array = hair.get("rest")
	var ppg: int = hair.get("points_per_guide")
	t.check(after[2].x > before[2].x + 0.01, "comb bends toward direction")
	t.near((after[1] - after[0]).length(), (before[1] - before[0]).length(), 0.0001, "segment length kept")
	var far_same := true
	for i in range(ppg, after.size()):
		if after[i] != before[i]:
			far_same = false
	t.check(far_same, "guides outside radius untouched")
	t.eq(after[0], before[0], "root fixed")

	t.current = "hair cut"
	var h2 := _make_hair()
	var b2: PackedVector3Array = (h2.get("rest") as PackedVector3Array).duplicate()
	gt.cut(h2, Vector3.ZERO, 0.1, 0.5)
	var a2: PackedVector3Array = h2.get("rest")
	t.near(a2[ppg - 1].distance_to(a2[0]), 0.2, 0.001, "cut halves length")
	t.eq(a2[0], b2[0], "cut keeps root")
	t.eq(a2[2 * ppg - 1], b2[2 * ppg - 1], "far guide not cut")

	t.current = "hair clump"
	var h3 := _make_hair()
	var s0: float = _tip_spread(h3)
	gt.clump(h3, PackedVector3Array([Vector3(0.4, -0.4, 0.0)]), 2.0, 1.0)
	t.check(_tip_spread(h3) < s0, "clump reduces tip spread")
	t.eq((h3.get("rest") as PackedVector3Array)[0], Vector3.ZERO, "clump keeps roots")

	t.current = "hair undo redo"
	var h4 := _make_hair()
	var gt2 := HairGroomTool.new()
	var orig: PackedVector3Array = (h4.get("rest") as PackedVector3Array).duplicate()
	gt2.cut(h4, Vector3.ZERO, 1.0, 0.5)
	gt2.noise(h4, Vector3.ZERO, 5.0, 0.05, 1)
	var edited: PackedVector3Array = (h4.get("rest") as PackedVector3Array).duplicate()
	t.check(gt2.undo(h4) and gt2.undo(h4), "undo twice")
	t.check(h4.get("rest") == orig, "undo restores original")
	t.check(not gt2.undo(h4), "undo stack empty")
	t.check(gt2.redo(h4) and gt2.redo(h4), "redo twice")
	t.check(h4.get("rest") == edited, "redo restores edits")

	t.current = "hair groom io"
	var data: Dictionary = gt2.export_groom(h4)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var h5 := HairStrands.new()
	t.check(parsed is Dictionary and gt2.import_groom(h5, parsed as Dictionary), "import via JSON")
	var r4: PackedVector3Array = h4.get("rest")
	var r5: PackedVector3Array = h5.rest
	t.eq(r5.size(), r4.size(), "point count round trip")
	t.eq(h5.guide_count, 5, "guide count round trip")
	var worst := 0.0
	for i in mini(r4.size(), r5.size()):
		worst = maxf(worst, r4[i].distance_to(r5[i]))
	t.near(worst, 0.0, 0.0001, "positions round trip")
	t.check(not gt2.import_groom(h5, {"guide_count": 1}), "malformed import rejected")
