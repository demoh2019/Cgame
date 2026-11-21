extends RefCounted
## World Partition bake, OFPA, diff, predictive streaming, navmesh stitching.

const WorldPartitionBake = preload("res://scripts/shared/world_partition_bake.gd")
const NavmeshStitching = preload("res://scripts/shared/navmesh_stitching.gd")


func _actor(guid: String, pos: Vector3, size: float, layers: PackedStringArray = PackedStringArray(), loaded: bool = true) -> Dictionary:
	return {
		"guid": guid, "position": pos, "bounds": AABB(pos - Vector3.ONE * size * 0.5, Vector3.ONE * size),
		"layers": layers, "spatially_loaded": loaded, "data": {"name": guid},
	}


func _actors() -> Array:
	return [
		_actor("a", Vector3(5, 0, 5), 2.0),
		_actor("b", Vector3(40, 0, 5), 2.0),
		_actor("c", Vector3(100, 0, 5), 2.0),
		_actor("big", Vector3(20, 0, 20), 50.0),
		_actor("sky", Vector3(0, 100, 0), 2.0, PackedStringArray(), false),
		_actor("night", Vector3(6, 0, 6), 2.0, PackedStringArray(["Night"])),
	]


func _tile(origin: Vector2, size: float) -> Dictionary:
	var o := origin
	var s := size
	var h := size * 0.5
	var p0 := PackedVector2Array([o, o + Vector2(h, 0), o + Vector2(h, s), o + Vector2(0, s)])
	var p1 := PackedVector2Array([o + Vector2(h, 0), o + Vector2(s, 0), o + Vector2(s, s), o + Vector2(h, s)])
	return {"origin": origin, "size": size, "polygons": [p0, p1]}


func run(t) -> void:
	var wp := WorldPartitionBake.new()
	var ranges := {"default": 40.0, "Night": 40.0}
	var result: Dictionary = wp.bake(_actors(), 32.0, ranges)
	var cells: Dictionary = result["cells"]

	t.current = "cell assignment"
	var a_cell := ""
	var big_cell := ""
	for k in cells:
		var key: String = k
		var members: Array = (cells[key] as Dictionary)["actors"]
		if "a" in members:
			a_cell = key
		if "big" in members:
			big_cell = key
	t.eq(a_cell, "|0|0|0", "actor at (5,5) in cell 0,0 level 0")
	t.check("b" in (cells["|0|1|0"] as Dictionary)["actors"], "actor at x=40 in cell x=1")
	t.check("c" in (cells["|0|3|0"] as Dictionary)["actors"], "actor at x=100 in cell x=3")
	t.check(int((cells[big_cell] as Dictionary)["level"]) > 0, "oversized actor goes to a coarser level")
	t.check(int((cells[a_cell] as Dictionary)["level"]) == 0, "small actor stays at level 0")
	var cb: AABB = (cells[a_cell] as Dictionary)["bounds"]
	t.check(cb.encloses(AABB(Vector3(4, -1, 4), Vector3(2, 2, 2))), "cell bounds enclose its actor")

	t.current = "always loaded and layers"
	var always: Array = result["always_loaded"]
	t.eq(always, ["sky"], "non spatially loaded actor is always loaded")
	var in_cells := false
	for k in cells:
		if "sky" in (cells[k] as Dictionary)["actors"]:
			in_cells = true
	t.check(not in_cells, "always loaded actor is in no cell")
	var layers: Dictionary = result["layers"]
	t.eq(layers["Night"], ["night"], "data layer membership recorded")
	var day_only: Array = wp.cells_to_load(Vector3(5, 0, 5), Vector3.ZERO, PackedStringArray())
	var with_night: Array = wp.cells_to_load(Vector3(5, 0, 5), Vector3.ZERO, PackedStringArray(["Night"]))
	t.check(not ("Night|0|0|0" in day_only), "disabled data layer cell not loaded")
	t.check("Night|0|0|0" in with_night, "enabled data layer cell loaded")
	t.check("|0|0|0" in day_only, "base cell loaded without layers")

	t.current = "guid stability"
	t.eq(wp.stable_guid("tree@12,4"), wp.stable_guid("tree@12,4"), "same seed same guid")
	t.check(wp.stable_guid("x") != wp.stable_guid("y"), "different seed different guid")
	var unnamed: Array = [{"position": Vector3(1, 0, 1), "spatially_loaded": true}]
	var r1: Dictionary = wp.bake(unnamed, 32.0, ranges)
	var r2: Dictionary = wp.bake(unnamed, 32.0, ranges)
	t.eq((r1["actors"] as Dictionary).keys(), (r2["actors"] as Dictionary).keys(), "generated guids survive rebake")
	result = wp.bake(_actors(), 32.0, ranges)

	t.current = "hlod"
	var clusters: Array = wp.hlod_clusters(cells, 2)
	t.check(clusters.size() > 0 and clusters.size() < cells.size(), "clusters merge cells")
	var contained := true
	var total_actors := 0
	for c in clusters:
		var cl: Dictionary = c
		var cbounds: AABB = cl["bounds"]
		for g in (cl["actors"] as Array):
			var info: Dictionary = (result["actors"] as Dictionary)[g]
			if not cbounds.encloses(info["bounds"]):
				contained = false
			total_actors += 1
	t.check(contained, "cluster bounds contain every member actor")
	t.eq(total_actors, 5, "every spatial actor in exactly one cluster")

	t.current = "one file per actor"
	var dir := "user://wp_ofpa_test"
	var written: int = wp.split_one_file_per_actor(_actors(), dir)
	t.eq(written, 6, "one file per actor written")
	var loaded: Array = wp.load_actors(dir)
	t.eq(loaded.size(), 6, "all actors read back")
	var found_big := false
	for l in loaded:
		var ld: Dictionary = l
		if ld["guid"] == "big":
			found_big = true
			var lb: AABB = ld["bounds"]
			t.near(lb.size.x, 50.0, 0.001, "bounds survive round trip")
			t.eq((ld["data"] as Dictionary)["name"], "big", "data survives round trip")
	t.check(found_big, "big actor loaded")
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))

	t.current = "diff"
	var newer: Array = _actors()
	newer.remove_at(2)
	newer[0] = _actor("a", Vector3(70, 0, 5), 2.0)
	newer.append(_actor("fresh", Vector3(10, 0, 10), 2.0))
	var old_bake: Dictionary = wp.bake(_actors(), 32.0, ranges)
	var new_bake: Dictionary = wp.bake(newer, 32.0, ranges)
	var diff: Dictionary = wp.diff_bakes(old_bake, new_bake)
	t.eq(diff["moved"], ["a"], "moved actor detected")
	t.eq(diff["added"], ["fresh"], "added actor detected")
	t.eq(diff["removed"], ["c"], "removed actor detected")
	t.check("|0|0|0" in (diff["dirty_cells"] as Array), "dirty cells include the old cell")

	t.current = "predictive streaming"
	wp.bake(_actors(), 32.0, ranges)
	var still: Array = wp.cells_to_load(Vector3(5, 0, 5), Vector3.ZERO, PackedStringArray())
	var moving: Array = wp.cells_to_load(Vector3(5, 0, 5), Vector3(60, 0, 0), PackedStringArray())
	t.check(not ("|0|3|0" in still), "far cell not loaded when standing still")
	t.check("|0|3|0" in moving, "cell ahead loaded by look-ahead")

	t.current = "navmesh stitching"
	var ta := _tile(Vector2(0, 0), 10.0)
	var tb := _tile(Vector2(10, 0), 10.0)
	var portals: Array = NavmeshStitching.stitch(ta, tb, 0.01)
	t.eq(portals.size(), 1, "one portal across the shared border")
	if portals.size() == 1:
		var p: Dictionary = portals[0]
		t.eq(p["poly_a"], 1, "portal poly in tile a")
		t.eq(p["poly_b"], 0, "portal poly in tile b")
		var pl: Vector2 = p["left"]
		var pr: Vector2 = p["right"]
		t.near(pl.x, 10.0, 0.001, "portal lies on the border")
		t.near(pl.y - pr.y, 10.0, 0.001, "portal spans the shared interval, left above right")
	t.eq(NavmeshStitching.stitch(ta, _tile(Vector2(30, 0), 10.0), 0.01).size(), 0, "distant tiles do not stitch")

	t.current = "navmesh pathing"
	var graph: Dictionary = NavmeshStitching.build_graph([ta, tb], 0.01)
	t.eq((graph["polys"] as Array).size(), 4, "graph holds every polygon")
	var path: PackedVector2Array = NavmeshStitching.find_path(graph, Vector2(1, 5), Vector2(19, 5))
	t.eq(path.size(), 2, "open corridor funnels to a straight line")
	t.check(path.size() >= 2 and path[0].is_equal_approx(Vector2(1, 5)) and path[path.size() - 1].is_equal_approx(Vector2(19, 5)), "path runs start to goal")
	var crosses := false
	for i in range(path.size() - 1):
		if path[i].x < 10.0 and path[i + 1].x > 10.0:
			crosses = true
	t.check(crosses, "path crosses the tile border")
	var diag: PackedVector2Array = NavmeshStitching.find_path(graph, Vector2(1, 1), Vector2(19, 9))
	t.eq(diag.size(), 2, "diagonal across tiles is also straight")
