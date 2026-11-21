extends RefCounted
## PCG graph runtime: typed pins, determinism, pruning/difference, spline sampling, subgraphs,
## custom nodes, incremental cache, debugger capture, partition cells and presets.

const PcgGraphScript = preload("res://scripts/shared/pcg_graph.gd")
const PCGPresets = preload("res://scripts/shared/pcg_presets.gd")


func _pts_with_density(positions: PackedVector3Array, dens: Array) -> Dictionary:
	var d: Dictionary = PcgGraphScript.make_points(positions)
	var attrs: Dictionary = d["attrs"]
	var arr: PackedFloat32Array = attrs["density"]
	for i in dens.size():
		arr[i] = float(dens[i])
	attrs["density"] = arr
	return d


func _origins(mesh_data: Dictionary) -> PackedVector3Array:
	var res := PackedVector3Array()
	var recs: Array = mesh_data["records"]
	for r: Dictionary in recs:
		var trs: Array = r["transforms"]
		for tr: Transform3D in trs:
			res.append(tr.origin)
	return res


func _landscape() -> Dictionary:
	return PcgGraphScript.make_landscape(func(x: float, z: float) -> float: return sin(x * 0.05) * 3.0 + cos(z * 0.07) * 2.0)


func _sampling_graph(prune: bool) -> PcgGraphScript:
	var g := PcgGraphScript.new()
	g.graph_seed = 77
	g.add_graph_input("in_v", "volume", "volume")
	g.add_node("sample", "surface_sampler", {"spacing": 3.0, "jitter": 0.8})
	g.add_node("noise", "density_noise", {"frequency": 0.05})
	g.add_node("filter", "density_filter", {"min": 0.3, "max": 1.0})
	g.add_graph_output("out", "pts", "points")
	g.link("in_v", "out", "sample", "volume")
	g.link("sample", "out", "noise", "in")
	g.link("noise", "out", "filter", "in")
	if prune:
		g.add_node("prune", "self_pruning", {"min_distance": 2.5})
		g.link("filter", "out", "prune", "in")
		g.link("prune", "out", "out", "in")
	else:
		g.link("filter", "out", "out", "in")
	return g


func _keyset(p: Dictionary) -> Dictionary:
	var res: Dictionary = {}
	var pos: PackedVector3Array = p["positions"]
	for v in pos:
		res["%.3f,%.3f,%.3f" % [v.x, v.y, v.z]] = true
	return res


func run(t) -> void:
	t.current = "typed pins"
	var g := PcgGraphScript.new()
	g.add_graph_input("in_v", "volume", "volume")
	g.add_node("sample", "surface_sampler")
	g.add_node("filter", "density_filter")
	t.check(g.link("in_v", "out", "sample", "landscape") != "", "volume into a landscape pin is rejected")
	t.check(g.link("in_v", "out", "filter", "in") != "", "volume into a points pin is rejected")
	t.check(g.link("in_v", "out", "sample", "nope") != "", "unknown pin is rejected")
	t.eq(g.link("in_v", "out", "sample", "volume"), "", "matching types connect")
	t.eq(g.link("sample", "out", "filter", "in"), "", "points into points connect")
	t.check(g.link("sample", "out", "filter", "in") != "", "a single-input pin takes only one edge")
	t.eq(g.validate().size(), 0, "valid graph has no errors")
	g.edges.append({"from": "in_v", "from_pin": "out", "to": "filter", "to_pin": "in"})
	t.check(g.validate().size() > 0, "validate reports an injected incompatible edge")
	t.eq(g.execute({}).size(), 0, "invalid graphs do not execute")
	t.check(g.last_errors.size() > 0, "errors are kept in last_errors")
	var cyc := PcgGraphScript.new()
	cyc.add_node("a", "density_filter")
	cyc.add_node("b", "density_filter")
	cyc.link("a", "out", "b", "in")
	cyc.link("b", "out", "a", "in")
	t.check(cyc.validate().size() > 0, "cycles are validation errors")
	t.check(PcgGraphScript.pins_compatible("any", "points") and not PcgGraphScript.pins_compatible("spline", "points"), "any is a wildcard")

	t.current = "determinism"
	var vol: Dictionary = PcgGraphScript.make_volume(AABB(Vector3(0, 0, 0), Vector3(60, 10, 60)))
	var ga := _sampling_graph(true)
	var gb := _sampling_graph(true)
	var oa: Dictionary = ga.execute({"volume": vol})
	var ob: Dictionary = gb.execute({"volume": vol})
	t.check(PcgGraphScript.point_count(oa["pts"]) > 50, "sampler produces points")
	t.eq(hash(oa), hash(ob), "same seed and inputs give identical output")
	gb.graph_seed = 78
	var oc: Dictionary = gb.execute({"volume": vol})
	t.check(hash(oa) != hash(oc), "a different seed changes the output")

	t.current = "self pruning"
	var gp := PcgGraphScript.new()
	gp.graph_seed = 5
	gp.add_graph_input("v", "volume", "volume")
	gp.add_node("s", "surface_sampler", {"spacing": 1.0, "jitter": 1.0})
	gp.add_node("p", "self_pruning", {"min_distance": 2.0})
	gp.add_graph_output("o", "pruned", "points")
	gp.add_graph_output("o0", "raw", "points")
	gp.link("v", "out", "s", "volume")
	gp.link("s", "out", "p", "in")
	gp.link("p", "out", "o", "in")
	gp.link("s", "out", "o0", "in")
	var po: Dictionary = gp.execute({"volume": PcgGraphScript.make_volume(AABB(Vector3.ZERO, Vector3(30, 5, 30)))})
	var pruned: Dictionary = po["pruned"]
	var pp: PackedVector3Array = pruned["positions"]
	var min_d: float = 1.0e9
	for i in pp.size():
		for j in range(i + 1, pp.size()):
			min_d = minf(min_d, pp[i].distance_to(pp[j]))
	t.check(min_d >= 2.0 - 0.0001, "survivors are at least min_distance apart (%f)" % min_d)
	t.check(PcgGraphScript.point_count(pruned) < PcgGraphScript.point_count(po["raw"]) and pp.size() > 10, "pruning removes some but not all points")

	t.current = "difference"
	var gd := PcgGraphScript.new()
	gd.add_graph_input("a", "a", "points")
	gd.add_graph_input("b", "b", "points")
	gd.add_node("d", "difference", {"distance": 2.0, "planar": true})
	gd.add_graph_output("o", "res", "points")
	gd.link("a", "out", "d", "in")
	gd.link("b", "out", "d", "other")
	gd.link("d", "out", "o", "in")
	var grid := PackedVector3Array()
	for x in range(0, 11):
		for z in range(0, 11):
			grid.append(Vector3(x, 0, z))
	var cut := PackedVector3Array([Vector3(5, 3, 5), Vector3(0, 0, 0)])
	var dr: Dictionary = gd.execute({"a": PcgGraphScript.make_points(grid), "b": PcgGraphScript.make_points(cut)})
	var res_pts: PackedVector3Array = (dr["res"] as Dictionary)["positions"]
	var ok_far: bool = true
	for p in res_pts:
		for c in cut:
			if Vector2(p.x - c.x, p.z - c.z).length() < 2.0:
				ok_far = false
	t.check(ok_far, "no remaining point is within the difference distance")
	t.check(res_pts.size() < grid.size() and res_pts.size() > grid.size() - 30, "only nearby points were removed")
	t.check(not res_pts.has(Vector3(5, 0, 5)) and res_pts.has(Vector3(10, 0, 10)), "centre removed, far corner kept")

	t.current = "spline sampler"
	var gs := PcgGraphScript.new()
	gs.add_graph_input("sp", "spline", "spline")
	gs.add_node("along", "spline_sampler", {"mode": "along", "spacing": 5.0})
	gs.add_node("off", "spline_sampler", {"mode": "along", "spacing": 5.0, "lateral_offset": 3.0})
	gs.add_node("around", "spline_sampler", {"mode": "around", "spacing": 2.0, "band_inner": 2.0, "band_outer": 6.0})
	gs.add_graph_output("o1", "along", "points")
	gs.add_graph_output("o2", "off", "points")
	gs.add_graph_output("o3", "around", "points")
	for n in ["along", "off", "around"]:
		gs.link("sp", "out", n, "spline")
	gs.link("along", "out", "o1", "in")
	gs.link("off", "out", "o2", "in")
	gs.link("around", "out", "o3", "in")
	var so: Dictionary = gs.execute({"spline": PcgGraphScript.make_spline(PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)]))})
	var along: PackedVector3Array = (so["along"] as Dictionary)["positions"]
	t.eq(along.size(), 21, "100 m at 5 m spacing gives 21 points")
	var spacing_ok: bool = true
	for i in range(1, along.size()):
		if absf(along[i].distance_to(along[i - 1]) - 5.0) > 0.001:
			spacing_ok = false
	t.check(spacing_ok, "consecutive points are spacing apart")
	var off_pts: PackedVector3Array = (so["off"] as Dictionary)["positions"]
	t.near(off_pts[3].z, 3.0, 0.001, "lateral offset moves points sideways")
	var around: PackedVector3Array = (so["around"] as Dictionary)["positions"]
	var band_ok: bool = around.size() == 102
	for p in around:
		if absf(p.z) < 2.0 - 0.001 or absf(p.z) > 6.0 + 0.001:
			band_ok = false
	t.check(band_ok, "around mode keeps points inside the band on both sides (%d)" % around.size())
	var bent: Dictionary = gs.execute({"spline": PcgGraphScript.make_spline(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]))})
	t.eq(((bent["along"] as Dictionary)["positions"] as PackedVector3Array).size(), 5, "a bent 20 m path at 5 m gives 5 points")

	t.current = "subgraph"
	var sub := PcgGraphScript.new()
	sub.add_graph_input("i", "in", "points")
	sub.add_node("f", "density_filter", {"min": 0.5})
	sub.add_node("x", "transform_points", {"scale_min": 2.0, "scale_max": 2.0, "rot_min_deg": 0.0, "rot_max_deg": 0.0})
	sub.add_graph_output("o", "out", "points")
	sub.link("i", "out", "f", "in")
	sub.link("f", "out", "x", "in")
	sub.link("x", "out", "o", "in")
	var par := PcgGraphScript.new()
	par.add_graph_input("ia", "a", "points")
	par.add_graph_input("ib", "b", "points")
	par.add_node("s1", "subgraph", {"graph": sub})
	par.add_node("s2", "subgraph", {"graph": sub})
	par.add_graph_output("oa", "ra", "points")
	par.add_graph_output("ob", "rb", "points")
	t.eq(par.link("ia", "out", "s1", "in"), "", "graph input feeds the subgraph input pin")
	t.eq(par.link("ib", "out", "s2", "in"), "", "same subgraph asset can be reused")
	t.check(par.link("ia", "out", "s1", "nope") != "", "subgraph pins come from its graph inputs")
	par.link("s1", "out", "oa", "in")
	par.link("s2", "out", "ob", "in")
	var pa: Dictionary = _pts_with_density(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)]), [0.2, 0.6, 0.9, 0.4])
	var pb: Dictionary = _pts_with_density(PackedVector3Array([Vector3(0, 0, 5), Vector3(1, 0, 5)]), [0.7, 0.1])
	var sr: Dictionary = par.execute({"a": pa, "b": pb})
	t.eq(PcgGraphScript.point_count(sr["ra"]), 2, "first instance filtered with its own inputs")
	t.eq(PcgGraphScript.point_count(sr["rb"]), 1, "second instance filtered independently")
	var sscale: PackedFloat32Array = ((sr["ra"] as Dictionary)["attrs"] as Dictionary)["scale"]
	t.near(sscale[0], 2.0, 0.0001, "subgraph nodes apply their params")
	t.check(par.executed_nodes.has("s1/f") and par.executed_nodes.has("s2/x"), "inner nodes are reported with a prefix")
	par.execute({"a": pa, "b": pb})
	t.eq(par.executed_nodes.size(), 0, "unchanged subgraph run is fully cached")
	var pb2: Dictionary = _pts_with_density(PackedVector3Array([Vector3(0, 0, 5), Vector3(1, 0, 5)]), [0.9, 0.9])
	var sr2: Dictionary = par.execute({"a": pa, "b": pb2})
	t.eq(PcgGraphScript.point_count(sr2["rb"]), 2, "changed input flows through the subgraph")
	var s1_ran: bool = false
	for n in par.executed_nodes:
		if n.begins_with("s1"):
			s1_ran = true
	t.check(not s1_ran, "the untouched subgraph instance stayed cached")

	t.current = "custom nodes"
	var gc := PcgGraphScript.new()
	gc.register_node("boost_density", {"in": "points"}, {"out": "points", "count_only": "points"}, func(inputs: Dictionary, params: Dictionary) -> Dictionary:
		var src: Dictionary = inputs["in"]
		var attrs: Dictionary = (src["attrs"] as Dictionary).duplicate()
		var dens: PackedFloat32Array = (attrs["density"] as PackedFloat32Array).duplicate()
		for i in dens.size():
			dens[i] *= float(params.get("factor", 2.0))
		attrs["density"] = dens
		var boosted: Dictionary = {"type": "points", "positions": src["positions"], "attrs": attrs}
		return {"out": boosted, "count_only": src})
	gc.add_graph_input("i", "p", "points")
	gc.add_node("b", "boost_density", {"factor": 3.0})
	gc.add_graph_output("o", "res", "points")
	t.eq(gc.link("i", "out", "b", "in"), "", "custom node pins validate")
	t.check(gc.link("b", "count_only", "o", "in") == "", "second custom output is linkable")
	t.check(gc.link("i", "out", "b", "other") != "", "custom node rejects unknown pins")
	var cr: Dictionary = gc.execute({"p": _pts_with_density(PackedVector3Array([Vector3.ZERO, Vector3.ONE]), [0.25, 0.5])})
	t.eq(PcgGraphScript.point_count(cr["res"]), 2, "custom output wired through")
	var gc2 := PcgGraphScript.new()
	gc2.register_node("boost_density", {"in": "points"}, {"out": "points"}, func(inputs: Dictionary) -> Dictionary:
		var src: Dictionary = inputs["in"]
		var attrs: Dictionary = (src["attrs"] as Dictionary).duplicate()
		var nd: PackedFloat32Array = (attrs["density"] as PackedFloat32Array).duplicate()
		nd.fill(0.9)
		attrs["density"] = nd
		return {"out": {"type": "points", "positions": src["positions"], "attrs": attrs}})
	gc2.add_graph_input("i", "p", "points")
	gc2.add_node("b", "boost_density")
	gc2.add_graph_output("o", "res", "points")
	gc2.link("i", "out", "b", "in")
	gc2.link("b", "out", "o", "in")
	var cr2: Dictionary = gc2.execute({"p": PcgGraphScript.make_points(PackedVector3Array([Vector3.ZERO]))})
	var cd: PackedFloat32Array = ((cr2["res"] as Dictionary)["attrs"] as Dictionary)["density"]
	t.near(cd[0], 0.9, 0.0001, "one-argument execute callables work")
	var unk := PcgGraphScript.new()
	unk.add_node("x", "no_such_node")
	t.check(unk.validate().size() > 0, "unknown node types are validation errors")

	t.current = "incremental cache"
	var gi := _sampling_graph(true)
	gi.add_node("spawn", "static_mesh_spawner", {"mesh_id": "tree"})
	gi.add_graph_output("out_m", "meshes", "mesh_instances")
	gi.link("prune", "out", "spawn", "in")
	gi.link("spawn", "out", "out_m", "in")
	var first: Dictionary = gi.execute({"volume": vol})
	t.eq(gi.executed_nodes.size(), gi.nodes.size(), "first run executes every node")
	var m1: Array = (first["meshes"] as Dictionary)["records"]
	t.check((m1[0] as Dictionary)["mesh_id"] == "tree", "spawner records the mesh id")
	gi.execute({"volume": vol})
	t.eq(gi.executed_nodes.size(), 0, "second identical run executes nothing")
	t.eq(gi.cache_hits, gi.nodes.size(), "every node was a cache hit")
	gi.set_param("filter", "min", 0.5)
	gi.execute({"volume": vol})
	var ran: Array[String] = gi.executed_nodes.duplicate()
	ran.sort()
	var expect: Array[String] = ["filter", "out", "out_m", "prune", "spawn"]
	expect.sort()
	t.eq(ran, expect, "only the changed node and its dependants re-run")
	gi.set_param("filter", "max", 5.0)
	gi.execute({"volume": vol})
	t.eq(gi.executed_nodes, ["filter"] as Array[String], "unchanged output stops propagation (early cutoff)")
	gi.set_param("sample", "spacing", 4.0)
	gi.execute({"volume": vol})
	t.check(gi.executed_nodes.has("sample") and gi.executed_nodes.has("spawn") and not gi.executed_nodes.has("in_v"), "upstream param change re-runs the chain but not the input")
	gi.execute({"volume": PcgGraphScript.make_volume(AABB(Vector3.ZERO, Vector3(40, 10, 40)))})
	t.check(gi.executed_nodes.has("sample"), "changed graph input invalidates dependants")

	t.current = "debug capture"
	gi.execute({"volume": vol})
	t.eq(gi.debug.size(), gi.nodes.size(), "every node is captured")
	t.eq(gi.debug_steps.size(), gi.nodes.size(), "steps list every node")
	var dbg: Dictionary = gi.debug["sample"]
	var outs: Dictionary = dbg["outputs"]
	var summ: Dictionary = outs["out"]
	t.check(int(summ["count"]) > 0, "output counts are recorded")
	t.check((summ["sample"] as Array).size() == 5, "sample points are limited to debug_sample_count")
	t.check(int(dbg["usec"]) >= 0 and bool(dbg["executed"]), "timing and executed flag are recorded")
	t.check(int((gi.debug["sample"] as Dictionary)["step"]) < int((gi.debug["prune"] as Dictionary)["step"]), "steps follow dependency order")
	var pdbg: Dictionary = gi.debug["prune"]
	t.check(int((pdbg["in_counts"] as Dictionary)["in"]) >= int(((pdbg["outputs"] as Dictionary)["out"] as Dictionary)["count"]), "input counts are captured")
	gi.execute({"volume": vol})
	t.check(not bool((gi.debug["sample"] as Dictionary)["executed"]), "cached nodes are flagged as not executed")
	gi.debug_capture_full = true
	gi.set_param("filter", "min", 0.6)
	gi.execute({"volume": vol})
	t.check((gi.debug["filter"] as Dictionary).has("full"), "full outputs can be captured for inspection")

	t.current = "partition cells"
	var cell: float = 20.0
	var gl := _sampling_graph(false)
	var whole: Dictionary = _keyset((gl.execute({"volume": vol}) as Dictionary)["pts"])
	var union: Dictionary = {}
	var dup_found: bool = false
	for cx in range(0, 3):
		for cz in range(0, 3):
			var part: Dictionary = gl.partition_execute(Vector2i(cx, cz), cell, {"volume": vol})
			var ks: Dictionary = _keyset(part["pts"])
			for k: String in ks:
				if union.has(k):
					dup_found = true
				union[k] = true
	t.check(whole.size() > 50, "unpartitioned run produced points")
	t.check(not dup_found, "no point appears in two cells")
	t.eq(union.size(), whole.size(), "cells together reproduce the unpartitioned result")
	var same_keys: bool = true
	for k: String in whole:
		if not union.has(k):
			same_keys = false
	t.check(same_keys, "positions at cell borders match exactly")
	var gq := _sampling_graph(true)
	var whole_p: Dictionary = _keyset((gq.execute({"volume": vol}) as Dictionary)["pts"])
	var union_p: Dictionary = {}
	for cx in range(0, 3):
		for cz in range(0, 3):
			var part_p: Dictionary = gq.partition_execute(Vector2i(cx, cz), cell, {"volume": vol}, 12.0)
			union_p.merge(_keyset(part_p["pts"]))
	t.eq(union_p.size(), whole_p.size(), "pruned cells with a margin match the unpartitioned run")
	var a1: Dictionary = gq.partition_execute(Vector2i(1, 1), cell, {"volume": vol}, 12.0)
	var a2: Dictionary = gq.partition_execute(Vector2i(1, 1), cell, {"volume": vol}, 12.0)
	t.eq(hash(a1), hash(a2), "re-running a cell is deterministic")

	t.current = "presets"
	var land: Dictionary = _landscape()
	var big: Dictionary = PcgGraphScript.make_volume(AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120)))
	var road: Dictionary = PcgGraphScript.make_spline(PackedVector3Array([Vector3(-60, 0, 0), Vector3(0, 0, 0), Vector3(60, 0, 0)]))
	var forest: PcgGraphScript = PCGPresets.forest_scatter()
	t.eq(forest.validate().size(), 0, "forest preset validates")
	var fo: Dictionary = forest.execute({"volume": big, "landscape": land, "road": road})
	var tree_pts: PackedVector3Array = _origins(fo["trees"])
	t.check(tree_pts.size() > 50, "forest produces trees (%d)" % tree_pts.size())
	var road_samples: PackedVector3Array = (forest.node_output("road_pts") as Dictionary)["positions"]
	var clear_ok: bool = true
	for p in tree_pts:
		for r in road_samples:
			if Vector2(p.x - r.x, p.z - r.z).length() < 7.0 - 0.001:
				clear_ok = false
	t.check(clear_ok, "no tree stands within the road clearing")
	t.eq(PcgGraphScript.point_count(fo["floor"]), tree_pts.size(), "forest floor layer weights match tree count")
	var ruins: PcgGraphScript = PCGPresets.ruins_debris()
	t.eq(ruins.validate().size(), 0, "ruins preset validates")
	var pois := PcgGraphScript.make_points(PackedVector3Array([Vector3(0, 0, 0), Vector3(40, 2, 10), Vector3(-30, 1, 25)]))
	var ro: Dictionary = ruins.execute({"pois": pois})
	t.check(PcgGraphScript.point_count(ro["debris"]) > 6, "ruins scatter debris around points of interest")
	t.check(PcgGraphScript.point_count(ro["ground"]) == PcgGraphScript.point_count(ro["debris"]), "rubble ground layer follows debris")
	var cave: PcgGraphScript = PCGPresets.cave_rocks()
	t.eq(cave.validate().size(), 0, "cave preset validates")
	var ents := PcgGraphScript.make_points(PackedVector3Array([Vector3(10, 0, 10), Vector3(-20, 3, 5)]))
	var co: Dictionary = cave.execute({"entrances": ents})
	var rocks: PackedVector3Array = _origins(co["rocks"])
	t.check(rocks.size() > 4, "cave entrances get rocks")
	var mouth_ok: bool = true
	for p in rocks:
		for e in [Vector3(10, 0, 10), Vector3(-20, 3, 5)]:
			if Vector2(p.x - e.x, p.z - e.z).length() < 3.0 - 0.001:
				mouth_ok = false
	t.check(mouth_ok, "cave mouths stay clear of rocks")
