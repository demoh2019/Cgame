extends RefCounted
## World tools: spline road/river/bridge authoring and foliage painting.

const SplineTool = preload("res://addons/cgame_world_tools/spline_tool.gd")
const FoliagePainter = preload("res://addons/cgame_world_tools/foliage_painter.gd")
const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")
const PcgGraphScript = preload("res://scripts/shared/pcg_graph.gd")

const N: int = 64


func _terrain(base_fn: Callable) -> TerrainEditLayers:
	var hs := PackedFloat32Array()
	hs.resize(N * N)
	for y in N:
		for x in N:
			hs[y * N + x] = float(base_fn.call(x, y))
	var tl := TerrainEditLayers.new()
	tl.setup(N, N, 16, hs)
	tl.setup_splat(3)
	return tl


func _line(tool: SplineTool, kind: String, xs: Array, z: float, y: float, w: float = 4.0) -> int:
	var id: int = tool.add_spline(kind)
	for x: float in xs:
		tool.add_point(id, Vector3(x, y, z), w)
	return id


func _min_dist(p: PackedVector3Array) -> float:
	var best: float = INF
	for i in p.size():
		for j in range(i + 1, p.size()):
			best = minf(best, Vector2(p[i].x, p[i].z).distance_to(Vector2(p[j].x, p[j].z)))
	return best


func _pcg() -> PcgGraphScript:
	var g := PcgGraphScript.new()
	g.graph_seed = 5
	g.add_graph_input("in_v", "volume", "volume")
	g.add_node("sample", "surface_sampler", {"spacing": 3.0, "jitter": 0.6})
	g.add_graph_output("out", "pts", "points")
	g.link("in_v", "out", "sample", "volume")
	g.link("sample", "out", "out", "in")
	return g


func run(t) -> void:
	_spline_editing(t)
	_road_and_river(t)
	_bridges_and_meshes(t)
	_flow(t)
	_foliage_paint(t)
	_foliage_pcg(t)
	_undo_redo(t)
	t.current = "plugin script"
	var plug: GDScript = load("res://addons/cgame_world_tools/plugin.gd")
	t.check(plug != null and plug.can_instantiate(), "plugin.gd compiles")


func _spline_editing(t) -> void:
	t.current = "spline point editing"
	var tool := SplineTool.new()
	t.eq(tool.add_spline("highway"), -1, "unknown kind rejected")
	var id: int = tool.add_spline("road")
	t.eq(tool.add_point(id, Vector3(0, 0, 0), 4.0), 0, "first point index")
	tool.add_point(id, Vector3(10, 0, 0), 6.0)
	tool.add_point(id, Vector3(20, 0, 0))
	t.eq(tool.point_count(id), 3, "three points")
	t.near(tool.get_point_width(id, 2), 6.0, 0.001, "new point inherits width")
	t.eq(tool.insert_point(id, 1, Vector3(5, 0, 2), 3.0), 1, "insert in the middle")
	t.eq(tool.point_count(id), 4, "four points after insert")
	t.eq(tool.get_point(id, 2), Vector3(10, 0, 0), "later points shift")
	t.check(tool.move_point(id, 1, Vector3(5, 1, 3)), "move point")
	t.eq(tool.get_point(id, 1), Vector3(5, 1, 3), "moved position stored")
	t.check(tool.set_point_width(id, 1, 8.0), "set width")
	t.near(tool.get_point_width(id, 1), 8.0, 0.001, "width stored")
	t.check(tool.delete_point(id, 0), "delete point")
	t.eq(tool.point_count(id), 3, "three points after delete")
	t.check(not tool.move_point(id, 9, Vector3.ZERO), "out of range move rejected")
	t.eq(tool.sample_spline(id, 4).size(), 2 * 4 + 1, "samples = segments*sps+1")


func _road_and_river(t) -> void:
	t.current = "road flatten (non-destructive)"
	var tl: TerrainEditLayers = _terrain(func(x: int, _y: int) -> float: return float(x) * 0.2)
	var layer: int = tl.add_layer("roads")
	var tool := SplineTool.new()
	_line(tool, "road", [10.0, 30.0, 50.0], 32.0, 5.0)
	var base_c: float = tl.composite_height(30, 32)
	t.near(base_c, 6.0, 0.001, "terrain slopes under the road")
	t.check(tool.apply(tl, layer), "apply succeeds")
	t.near(tl.composite_height(30, 32), 5.0, 0.01, "road bed flattened to spline height")
	t.near(tl.composite_height(20, 32), 5.0, 0.01, "flat along the road")
	t.near(tl.composite_height(30, 2), 6.0, 0.001, "far terrain untouched")
	t.check(tl.splat_weights(30, 32)[1] > 0.9, "road material painted along the spline")
	t.near(tl.splat_weights(30, 2)[1], 0.0, 0.001, "no road material away from it")
	tl.set_layer_visible(layer, false)
	t.near(tl.composite_height(30, 32), 6.0, 0.001, "hiding the layer restores terrain")
	tl.set_layer_visible(layer, true)
	tool.apply(tl, layer)
	t.near(tl.composite_height(30, 32), 5.0, 0.01, "re-apply is idempotent")
	var bank: float = tl.composite_height(30, 36)
	t.check(bank > 5.0 and bank < 6.0, "embankment falloff blends")

	t.current = "per-point width"
	var tl2: TerrainEditLayers = _terrain(func(_x: int, _y: int) -> float: return 0.0)
	var l2: int = tl2.add_layer("roads")
	var tw := SplineTool.new()
	var id2: int = tw.add_spline("road")
	tw.add_point(id2, Vector3(8, 4, 32), 2.0)
	tw.add_point(id2, Vector3(56, 4, 32), 16.0)
	tw.set_spline_params(id2, {"falloff": 0.5})
	tw.apply(tl2, l2)
	t.near(tl2.composite_height(10, 36), 0.0, 0.2, "narrow end leaves the verge")
	t.near(tl2.composite_height(54, 38), 4.0, 0.2, "wide end covers the verge")

	t.current = "river carve"
	var tl3: TerrainEditLayers = _terrain(func(_x: int, _y: int) -> float: return 3.0)
	var l3: int = tl3.add_layer("water")
	var tr := SplineTool.new()
	_line(tr, "river", [5.0, 32.0, 60.0], 32.0, 3.0, 6.0)
	tr.apply(tl3, l3)
	t.near(tl3.composite_height(32, 32), 2.0, 0.01, "river centre carved below the bed")
	t.near(tl3.composite_height(32, 2), 3.0, 0.001, "outside the channel untouched")
	t.check(tl3.composite_height(32, 34) > 2.0 and tl3.composite_height(32, 34) < 3.0, "banks slope up")
	t.check(tl3.splat_weights(32, 32)[2] > 0.9, "river material painted")

	t.current = "embankment raise"
	var tl4: TerrainEditLayers = _terrain(func(x: int, _y: int) -> float: return 8.0 if x > 40 else 0.0)
	var l4: int = tl4.add_layer("embank")
	var te := SplineTool.new()
	var ide: int = _line(te, "road", [10.0, 50.0], 32.0, 4.0)
	te.set_spline_params(ide, {"mode": "raise"})
	te.apply(tl4, l4)
	t.near(tl4.composite_height(20, 32), 4.0, 0.01, "raise lifts low ground")
	t.near(tl4.composite_height(48, 32), 8.0, 0.01, "raise never lowers high ground")


func _bridges_and_meshes(t) -> void:
	t.current = "bridge segments"
	var tl: TerrainEditLayers = _terrain(func(x: int, _y: int) -> float: return 0.0 if x >= 25 and x <= 35 else 5.0)
	var tool := SplineTool.new()
	var id: int = _line(tool, "road", [4.0, 32.0, 60.0], 32.0, 5.0, 4.0)
	var heights: PackedFloat32Array = tool.terrain_heights_without(tl)
	var spans: Array = tool.bridge_segments(heights, N, N, 1.0, 2.0, 16)
	t.eq(spans.size(), 1, "one bridge span over the ravine")
	var sp: Dictionary = spans[0]
	t.eq(int(sp["spline_id"]), id, "span belongs to the road")
	var pts: PackedVector3Array = sp["points"]
	t.check(pts.size() >= 2, "span has samples")
	t.check(pts[0].x > 22.0 and pts[0].x < 31.0, "span starts at the ravine edge")
	t.check(pts[pts.size() - 1].x > 31.0 and pts[pts.size() - 1].x < 38.0, "span ends at the far edge")
	t.check(float(sp["length"]) > 5.0, "span length reported")
	t.eq(tool.bridge_segments(heights, N, N, 1.0, 9.0).size(), 0, "no span when clearance is large")

	t.current = "bridge mesh"
	var m1: ArrayMesh = tool.build_bridge_mesh(sp, 4.0, 0.5, 4.0, func(_x: float, _z: float) -> float: return 0.0)
	var m2: ArrayMesh = tool.build_bridge_mesh(sp, 4.0, 0.5, 4.0, func(_x: float, _z: float) -> float: return 100.0)
	t.eq(m1.get_surface_count(), 1, "bridge has one surface")
	var v1: PackedVector3Array = m1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var v2: PackedVector3Array = m2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	t.check(v2.size() > 0, "deck has vertices")
	t.check(v1.size() > v2.size(), "supports add geometry when ground is below the deck")
	var low: float = INF
	for v in v1:
		low = minf(low, v.y)
	t.near(low, 0.0, 0.001, "supports reach the ground")
	t.eq(tool.build_bridge_mesh({}).get_surface_count(), 0, "empty span gives empty mesh")

	t.current = "road mesh"
	var tr := SplineTool.new()
	_line(tr, "road", [0.0, 20.0, 40.0], 10.0, 0.0, 6.0)
	var rm: ArrayMesh = tr.build_road_mesh(6.0, 0.5, -1, func(x: float, _z: float) -> float: return x * 0.2, 8, 0.05)
	var arr: Array = rm.surface_get_arrays(0)
	var rv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ri: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	t.eq(rv.size(), 2 * (2 * 8 + 1), "two vertices per spline sample")
	t.eq(ri.size(), 6 * (2 * 8), "two triangles per segment")
	var follows: bool = true
	for v in rv:
		if absf(v.y - (v.x * 0.2 + 0.05)) > 0.001:
			follows = false
	t.check(follows, "ribbon follows terrain height")
	t.near(absf(rv[0].z - rv[1].z), 6.0, 0.001, "ribbon has the requested width")
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	t.near(uv[uv.size() - 1].y, 40.0 * 0.5, 0.01, "uv follows distance * scale")
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	t.check(nrm[0].y > 0.9, "normals face up")
	var tri_up: bool = true
	for k in range(0, ri.size(), 3):
		var n: Vector3 = (rv[ri[k + 2]] - rv[ri[k]]).cross(rv[ri[k + 1]] - rv[ri[k]])
		if n.y <= 0.0:
			tri_up = false
	t.check(tri_up, "triangle winding faces up")
	t.eq(SplineTool.new().build_road_mesh().get_surface_count(), 0, "no road, no mesh")


func _flow(t) -> void:
	t.current = "river flow map"
	var tool := SplineTool.new()
	var id: int = _line(tool, "river", [4.0, 32.0, 60.0], 32.0, 0.0, 8.0)
	var rect := Rect2(0, 0, 64, 64)
	var img: Image = tool.river_flow_map(id, rect, Vector2i(64, 64))
	var c: Color = img.get_pixel(32, 32)
	t.check(c.r > 0.95, "flow points along +X")
	t.near(c.g, 0.5, 0.05, "no Z component")
	t.near(c.a, 1.0, 0.001, "inside the channel")
	t.check(c.b > 0.8, "fast at the centre")
	var edge: Color = img.get_pixel(32, 35)
	t.check(edge.b < c.b, "slower toward the bank")
	t.near(img.get_pixel(32, 5).a, 0.0, 0.001, "outside the channel is masked")
	var rev := SplineTool.new()
	var rid: int = _line(rev, "river", [60.0, 32.0, 4.0], 32.0, 0.0, 8.0)
	t.check(rev.river_flow_map(rid, rect, Vector2i(64, 64)).get_pixel(32, 32).r < 0.05, "reversed spline flows -X")
	var diag := SplineTool.new()
	var did: int = diag.add_spline("river")
	diag.add_point(did, Vector3(10, 0, 10), 8.0)
	diag.add_point(did, Vector3(50, 0, 50), 8.0)
	var dc: Color = diag.river_flow_map(did, rect, Vector2i(64, 64)).get_pixel(30, 30)
	t.check(dc.r > 0.8 and dc.g > 0.8, "diagonal flow has both components")


func _foliage_paint(t) -> void:
	t.current = "foliage paint density and spacing"
	var fp := FoliagePainter.new()
	fp.set_rules("grass", {"spacing": 1.0})
	var added: int = fp.paint(Vector3.ZERO, 10.0, "grass", 0.5, 1)
	var target: float = 0.5 * PI * 100.0
	t.eq(fp.count("grass"), added, "count matches return value")
	t.check(float(added) > target * 0.5 and float(added) <= target + 1.0, "density near target (%d of %.0f)" % [added, target])
	var p: PackedVector3Array = fp.positions("grass")
	t.check(_min_dist(p) >= 1.0 - 0.0001, "Poisson spacing respected")
	var inside: bool = true
	for v in p:
		if Vector2(v.x, v.z).length() > 10.001:
			inside = false
	t.check(inside, "all instances inside the brush")
	var again: int = fp.paint(Vector3.ZERO, 10.0, "grass", 0.5, 2)
	t.check(again <= int(target * 0.5), "repainting saturates instead of doubling (%d)" % again)
	t.check(_min_dist(fp.positions("grass")) >= 1.0 - 0.0001, "spacing holds across strokes")
	var a2: PackedVector3Array = FoliagePainter.new().positions("grass")
	t.eq(a2.size(), 0, "unknown type is empty")
	var f2 := FoliagePainter.new()
	f2.set_rules("grass", {"spacing": 1.0})
	f2.paint(Vector3.ZERO, 10.0, "grass", 0.5, 1)
	t.eq(f2.count("grass"), added, "same seed is deterministic")

	t.current = "foliage slope and height rules"
	var fs := FoliagePainter.new()
	fs.height_at = func(x: float, _z: float) -> float: return x * 2.0
	fs.set_rules("pine", {"spacing": 1.0, "max_slope_deg": 30.0})
	t.eq(fs.paint(Vector3.ZERO, 8.0, "pine", 1.0, 3), 0, "steep terrain rejects instances")
	var fh := FoliagePainter.new()
	fh.height_at = func(x: float, _z: float) -> float: return x * 0.1
	fh.set_rules("pine", {"spacing": 1.0, "min_height": 0.0, "max_height": 0.5})
	t.check(fh.paint(Vector3.ZERO, 10.0, "pine", 0.5, 4) > 5, "gentle terrain accepts")
	var band_ok: bool = true
	for v in fh.positions("pine"):
		if v.y < -0.0001 or v.y > 0.5001 or absf(v.y - v.x * 0.1) > 0.0001:
			band_ok = false
	t.check(band_ok, "height band respected and instances sit on the terrain")

	t.current = "foliage erase"
	var before: int = fp.count("grass")
	var removed: int = fp.erase(Vector3.ZERO, 4.0, "grass")
	t.check(removed > 0, "erase removes instances")
	t.eq(fp.count("grass"), before - removed, "count drops by the erased amount")
	var clear: bool = true
	for v in fp.positions("grass"):
		if Vector2(v.x, v.z).length() <= 4.0:
			clear = false
	t.check(clear, "nothing left inside the erase brush")
	t.check(fp.count("grass") > 0, "instances outside survive")
	t.eq(fp.erase(Vector3(500, 0, 500), 2.0, "grass"), 0, "erase far away removes nothing")

	t.current = "density mask"
	var fm := FoliagePainter.new()
	fm.set_rules("grass", {"spacing": 0.5})
	var full: int = fm.paint(Vector3.ZERO, 10.0, "grass", 0.8, 9)
	var fm2 := FoliagePainter.new()
	fm2.set_rules("grass", {"spacing": 0.5})
	fm2.paint_density_mask("grass", Vector3.ZERO, 30.0, 0.25)
	t.near(fm2.mask_at("grass", 0.0, 0.0), 0.25, 0.01, "mask painted")
	t.near(fm2.mask_at("grass", 100.0, 100.0), 1.0, 0.001, "unpainted area is full density")
	var masked: int = fm2.paint(Vector3.ZERO, 10.0, "grass", 0.8, 9)
	t.check(masked < int(float(full) * 0.6), "mask reduces painted count (%d < %d)" % [masked, full])
	var fm3 := FoliagePainter.new()
	fm3.paint_density_mask("grass", Vector3.ZERO, 30.0, 0.0)
	t.eq(fm3.paint(Vector3.ZERO, 10.0, "grass", 0.8, 9), 0, "zero mask blocks painting")


func _foliage_pcg(t) -> void:
	t.current = "pcg merge, mask and overrides"
	var g: PcgGraphScript = _pcg()
	var inputs: Dictionary = {"volume": PcgGraphScript.make_volume(AABB(Vector3(-20, 0, -20), Vector3(40, 10, 40)))}
	var fp := FoliagePainter.new()
	var n: int = fp.regenerate_from_pcg(g, inputs, "tree")
	t.check(n > 50, "graph produced procedural instances (%d)" % n)
	t.eq(fp.count("tree"), n, "all instances in the layer")
	t.eq(fp.procedural_count("tree"), n, "all flagged procedural")
	t.eq(fp.regenerate_from_pcg(PcgGraphScript.new(), {}, "tree"), -1, "non-point output rejected")

	var id: int = fp.instance_id("tree", 3)
	var far := Vector3(100, 0, 100)
	t.check(fp.edit_instance("tree", 3, Transform3D(Basis(Vector3.UP, 1.0).scaled(Vector3.ONE * 2.0), far)), "edit instance")
	t.check(fp.is_overridden("tree", id), "override recorded by stable id")
	var kill_id: int = fp.instance_id("tree", 10)
	fp.erase(fp.positions("tree")[10], 0.01, "tree")
	var n2: int = fp.regenerate_from_pcg(g, inputs, "tree")
	t.eq(n2, n - 1, "regeneration keeps the erased instance deleted")
	var idx: int = fp.index_of_id("tree", id)
	t.check(idx >= 0, "edited instance survives regeneration")
	t.eq(fp.positions("tree")[idx], far, "override position re-applied")
	var xf: Transform3D = fp.instance_transform("tree", idx)
	t.near(xf.basis.get_scale().x, 2.0, 0.001, "override scale re-applied")
	t.eq(fp.index_of_id("tree", kill_id), -1, "deleted instance stays gone")
	t.eq(fp.override_count("tree"), 2, "two overrides held")
	t.check(fp.revert_instance("tree", id), "revert override")
	t.check(fp.positions("tree")[fp.index_of_id("tree", id)].distance_to(far) > 1.0, "revert restores generated position")

	t.current = "manual instances survive regeneration"
	fp.set_rules("tree", {"spacing": 2.0})
	var manual: int = fp.paint(Vector3(0, 0, 0), 3.0, "tree", 0.1, 5)
	var total: int = fp.count("tree")
	var proc_before: int = fp.procedural_count("tree")
	fp.regenerate_from_pcg(g, inputs, "tree")
	t.eq(fp.count("tree") - fp.procedural_count("tree"), total - proc_before, "painted instances kept (%d)" % manual)

	t.current = "mask scales procedural output"
	var fq := FoliagePainter.new()
	var full: int = fq.regenerate_from_pcg(g, inputs, "tree")
	fq.paint_density_mask("tree", Vector3.ZERO, 60.0, 0.5)
	var half: int = fq.procedural_count("tree")
	t.check(half < int(float(full) * 0.75) and half > int(float(full) * 0.25), "mask halves procedural count (%d of %d)" % [half, full])
	fq.paint_density_mask("tree", Vector3.ZERO, 60.0, 0.0, 1.0)
	t.eq(fq.procedural_count("tree"), 0, "zero mask clears procedural output")
	t.check(fq.undo(), "undo mask")
	t.eq(fq.procedural_count("tree"), half, "undo restores procedural instances")

	t.current = "multimesh"
	var mm: MultiMesh = fq.to_multimesh("tree", BoxMesh.new())
	t.eq(mm.instance_count, fq.count("tree"), "multimesh holds every instance")
	t.eq(mm.transform_format, MultiMesh.TRANSFORM_3D, "3D transforms")


func _undo_redo(t) -> void:
	t.current = "foliage undo/redo"
	var fp := FoliagePainter.new()
	fp.set_rules("grass", {"spacing": 1.0})
	t.check(not fp.undo(), "nothing to undo initially")
	var n: int = fp.paint(Vector3.ZERO, 6.0, "grass", 0.5, 1)
	var e: int = fp.erase(Vector3.ZERO, 3.0, "grass")
	t.check(e > 0, "erased something")
	t.check(fp.undo(), "undo erase")
	t.eq(fp.count("grass"), n, "erase undone")
	t.check(fp.undo(), "undo paint")
	t.eq(fp.count("grass"), 0, "paint undone")
	t.check(fp.redo(), "redo paint")
	t.eq(fp.count("grass"), n, "paint redone")
	t.check(fp.redo(), "redo erase")
	t.eq(fp.count("grass"), n - e, "erase redone")
	t.check(not fp.redo(), "redo stack exhausted")

	t.current = "spline undo/redo"
	var tool := SplineTool.new()
	var id: int = _line(tool, "road", [10.0, 30.0, 50.0], 32.0, 5.0)
	tool.move_point(id, 1, Vector3(30, 9, 32))
	t.check(tool.undo(), "undo move")
	t.eq(tool.get_point(id, 1), Vector3(30, 5, 32), "move undone")
	t.check(tool.redo(), "redo move")
	t.eq(tool.get_point(id, 1), Vector3(30, 9, 32), "move redone")
	tool.delete_point(id, 0)
	t.eq(tool.point_count(id), 2, "deleted")
	tool.undo()
	t.eq(tool.point_count(id), 3, "delete undone")
	t.near(tool.get_point_width(id, 0), 4.0, 0.001, "width restored with the point")

	t.current = "apply undo/redo"
	var tl: TerrainEditLayers = _terrain(func(x: int, _y: int) -> float: return float(x) * 0.2)
	var layer: int = tl.add_layer("roads")
	var t2 := SplineTool.new()
	_line(t2, "road", [10.0, 30.0, 50.0], 32.0, 5.0)
	var depth0: int = tl.undo_depth()
	t2.apply(tl, layer)
	t.check(tl.undo_depth() > depth0, "apply recorded terrain history")
	t.near(tl.composite_height(30, 32), 5.0, 0.01, "applied")
	t.check(t2.undo(), "undo apply")
	t.near(tl.composite_height(30, 32), 6.0, 0.001, "terrain restored by undo")
	t.eq(tl.undo_depth(), depth0, "terrain history unwound")
	t.check(t2.redo(), "redo apply")
	t.near(tl.composite_height(30, 32), 5.0, 0.01, "apply redone")
