extends RefCounted
## Recast-style navmesh baker: voxelization, filters, erosion, regions,
## contours, convex polygons, tiling, async baking and stitching.

const Baker = preload("res://scripts/shared/navmesh_baker.gd")
const Stitching = preload("res://scripts/shared/navmesh_stitching.gd")


func _make_baker(max_verts: int = 6) -> Baker:
	var b := Baker.new()
	b.configure({
		"cell_size": 0.25, "cell_height": 0.1, "agent_height": 1.8, "agent_radius": 0.5,
		"agent_max_climb": 0.4, "agent_max_slope_deg": 45.0, "region_min_area": 4,
		"max_verts_per_poly": max_verts, "tile_size": 10.0, "max_simplification_error": 0.5,
	})
	return b


## Up-facing (ccw from above) or down-facing horizontal quad.
func _quad(tris: PackedVector3Array, x0: float, z0: float, x1: float, z1: float, y: float, up: bool) -> void:
	var a := Vector3(x0, y, z0)
	var b := Vector3(x0, y, z1)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x1, y, z0)
	if up:
		tris.append_array(PackedVector3Array([a, b, c, a, c, d]))
	else:
		tris.append_array(PackedVector3Array([a, c, b, a, d, c]))


func _wall(tris: PackedVector3Array, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float) -> void:
	var a := Vector3(x0, y0, z0)
	var b := Vector3(x1, y0, z1)
	var c := Vector3(x1, y1, z1)
	var d := Vector3(x0, y1, z0)
	tris.append_array(PackedVector3Array([a, b, c, a, c, d]))


func _box(tris: PackedVector3Array, x0: float, z0: float, x1: float, z1: float, h: float, top_up: bool) -> void:
	_wall(tris, x0, z0, x1, z0, 0.0, h)
	_wall(tris, x1, z0, x1, z1, 0.0, h)
	_wall(tris, x1, z1, x0, z1, 0.0, h)
	_wall(tris, x0, z1, x0, z0, 0.0, h)
	_quad(tris, x0, z0, x1, z1, h, top_up)


func _in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		if (poly[i].y > p.y) != (poly[j].y > p.y) and p.x < (poly[j].x - poly[i].x) * (p.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x:
			inside = not inside
		j = i
	return inside


func _covered(tile: Dictionary, x: float, z: float) -> bool:
	var polys: Array = tile["polygons"]
	for p in polys:
		if _in_poly(Vector2(x, z), p as PackedVector2Array):
			return true
	return false


func _area(tile: Dictionary) -> float:
	var total := 0.0
	var polys: Array = tile["polygons"]
	for p in polys:
		var poly: PackedVector2Array = p
		var a := 0.0
		for i in poly.size():
			var q: Vector2 = poly[(i + 1) % poly.size()]
			a += poly[i].x * q.y - q.x * poly[i].y
		total += absf(a) * 0.5
	return total


func _max_height_at(tile: Dictionary, x: float, z: float) -> float:
	var best := -1000.0
	var polys: Array = tile["polygons"]
	var hts: Array = tile["heights"]
	for i in polys.size():
		if _in_poly(Vector2(x, z), polys[i] as PackedVector2Array):
			var hs: PackedFloat32Array = hts[i]
			for h in hs:
				best = maxf(best, h)
	return best


func _all_convex(tile: Dictionary, max_verts: int) -> bool:
	var polys: Array = tile["polygons"]
	for p in polys:
		var poly: PackedVector2Array = p
		if poly.size() < 3 or poly.size() > max_verts:
			return false
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			var c: Vector2 = poly[(i + 2) % poly.size()]
			if (b - a).cross(c - b) < -0.0001:
				return false
	return true


func run(t) -> void:
	var plane := PackedVector3Array()
	_quad(plane, 0.0, 0.0, 10.0, 10.0, 0.0, true)
	var bounds := AABB(Vector3(0, 0, 0), Vector3(10, 4, 10))

	t.current = "flat plane"
	var baker := _make_baker()
	var flat: Dictionary = baker.bake_tile(plane, bounds)
	var flat_polys: Array = flat["polygons"]
	t.check(flat_polys.size() > 0, "plane produces polygons")
	t.eq((flat["heights"] as Array).size(), flat_polys.size(), "one height array per polygon")
	t.eq(flat["origin"], Vector2(0, 0), "tile origin")
	t.near(float(flat["size"]), 10.0, 0.0001, "tile size")
	var flat_area: float = _area(flat)
	# radius 0.5 border (+ one ledge cell at the world edge): inner square ~8.5^2
	t.check(flat_area > 64.0 and flat_area < 81.0, "plane area is the plane minus the agent border (%f)" % flat_area)
	t.check(_covered(flat, 5.0, 5.0), "centre walkable")
	t.check(_covered(flat, 1.2, 1.2) and _covered(flat, 8.8, 8.8), "area beyond the border is walkable")
	t.check(not _covered(flat, 0.3, 5.0) and not _covered(flat, 9.7, 5.0) and not _covered(flat, 5.0, 0.3) and not _covered(flat, 5.0, 9.7),
		"agent-radius border is excluded")
	t.check(_all_convex(flat, 6), "polygons convex and within max verts")
	t.check(absf(_max_height_at(flat, 5.0, 5.0)) < 0.3, "heights follow the floor")

	t.current = "box obstacle"
	var boxed := plane.duplicate()
	_box(boxed, 4.0, 4.0, 6.0, 6.0, 1.5, false)
	var holed: Dictionary = baker.bake_tile(boxed, bounds)
	t.check(not _covered(holed, 5.0, 5.0), "box interior excluded")
	t.check(not _covered(holed, 3.7, 5.0) and not _covered(holed, 5.0, 6.3), "agent radius around the box excluded")
	t.check(_covered(holed, 2.0, 5.0) and _covered(holed, 8.0, 5.0) and _covered(holed, 5.0, 2.0) and _covered(holed, 5.0, 8.0),
		"space around the box stays walkable")
	var holed_area: float = _area(holed)
	t.check(holed_area < flat_area - 8.0 and holed_area > flat_area - 20.0, "hole removes area (%f vs %f)" % [holed_area, flat_area])
	t.check(_all_convex(holed, 6), "polygons around a hole are convex")

	t.current = "convex limits"
	for nvp in [3, 4, 6, 8]:
		var nb := _make_baker(nvp)
		var tile_n: Dictionary = nb.bake_tile(boxed, bounds)
		t.check((tile_n["polygons"] as Array).size() > 0, "bakes with max verts %d" % nvp)
		t.check(_all_convex(tile_n, nvp), "convex within %d verts" % nvp)
		t.near(_area(tile_n), holed_area, 0.5, "merging does not change covered area (%d)" % nvp)

	t.current = "ramps"
	var gentle := PackedVector3Array()
	_quad(gentle, -6.0, 0.0, 0.0, 6.0, 0.0, true)
	var ga := Vector3(0, 0, 0)
	var gb := Vector3(0, 0, 6)
	var gc := Vector3(6, 1.6, 6)
	var gd := Vector3(6, 1.6, 0)
	gentle.append_array(PackedVector3Array([ga, gb, gc, ga, gc, gd]))
	var gentle_tile: Dictionary = baker.bake_tile(gentle, AABB(Vector3(-6, 0, 0), Vector3(12, 4, 6)))
	t.check(_covered(gentle_tile, -3.0, 3.0), "floor before the gentle ramp walkable")
	t.check(_covered(gentle_tile, 3.0, 3.0), "15 degree ramp is walkable")
	t.check(_max_height_at(gentle_tile, 3.0, 3.0) > 0.4, "walkable ramp polygons rise with the ramp")
	var steep := PackedVector3Array()
	_quad(steep, -6.0, 0.0, 0.0, 6.0, 0.0, true)
	var sc := Vector3(4, 6.9, 6)
	var sd := Vector3(4, 6.9, 0)
	steep.append_array(PackedVector3Array([ga, gb, sc, ga, sc, sd]))
	var steep_tile: Dictionary = baker.bake_tile(steep, AABB(Vector3(-6, 0, 0), Vector3(10, 10, 6)))
	t.check(_covered(steep_tile, -3.0, 3.0), "floor before the steep ramp walkable")
	t.check(not _covered(steep_tile, 2.0, 3.0), "60 degree ramp excluded")

	t.current = "head clearance"
	var low := plane.duplicate()
	_quad(low, 0.0, 0.0, 5.0, 10.0, 1.0, false)
	var low_tile: Dictionary = baker.bake_tile(low, bounds)
	t.check(not _covered(low_tile, 2.5, 5.0), "space under a 1m ceiling excluded")
	t.check(_covered(low_tile, 7.5, 5.0), "open space stays walkable")
	var high := plane.duplicate()
	_quad(high, 0.0, 0.0, 5.0, 10.0, 3.0, false)
	var high_tile: Dictionary = baker.bake_tile(high, bounds)
	t.check(_covered(high_tile, 2.5, 5.0), "space under a 3m ceiling is walkable")

	t.current = "step climb"
	var small_step := plane.duplicate()
	_box(small_step, 4.0, 4.0, 8.0, 8.0, 0.3, true)
	var small_tile: Dictionary = baker.bake_tile(small_step, bounds)
	t.check(_covered(small_tile, 6.0, 6.0), "step top walkable")
	t.check(_covered(small_tile, 3.6, 6.0), "floor next to a climbable step is not eroded")
	var tall_step := plane.duplicate()
	_box(tall_step, 4.0, 4.0, 8.0, 8.0, 0.8, true)
	var tall_tile: Dictionary = baker.bake_tile(tall_step, bounds)
	t.check(_covered(tall_tile, 6.0, 6.0), "tall platform top is a separate walkable surface")
	t.check(not _covered(tall_tile, 3.6, 6.0), "floor next to an unclimbable ledge is eroded")

	t.current = "async tiles"
	var wide := PackedVector3Array()
	_quad(wide, 0.0, 0.0, 20.0, 10.0, 0.0, true)
	_box(wide, 4.0, 4.0, 6.0, 6.0, 1.5, false)
	var wide_bounds := AABB(Vector3(0, 0, 0), Vector3(20, 4, 10))
	var rects: Array[AABB] = baker.tile_rects(wide_bounds)
	t.eq(rects.size(), 2, "two tiles")
	var job: int = baker.bake_async(wide, wide_bounds)
	var res: Dictionary = {"done": false, "tiles": []}
	var deadline: int = Time.get_ticks_msec() + 20000
	while not bool(res["done"]) and Time.get_ticks_msec() < deadline:
		res = baker.poll(job)
		if not bool(res["done"]):
			OS.delay_msec(5)
	t.check(bool(res["done"]), "async job finishes")
	var tiles: Array = res["tiles"]
	t.eq(tiles.size(), 2, "one result per tile")
	var identical := tiles.size() == rects.size()
	for i in mini(tiles.size(), rects.size()):
		var sync_tile: Dictionary = baker.bake_tile(wide, rects[i])
		var async_tile: Dictionary = tiles[i]
		var sp: Array = sync_tile["polygons"]
		var ap: Array = async_tile["polygons"]
		if sp.size() != ap.size() or sp.is_empty():
			identical = false
			continue
		for k in sp.size():
			if sp[k] != ap[k]:
				identical = false
		if sync_tile["heights"] != async_tile["heights"] or sync_tile["origin"] != async_tile["origin"]:
			identical = false
	t.check(identical, "async result equals sync bake")
	t.check(baker.poll(job)["done"], "finished job stays done")

	t.current = "tile stitching"
	if tiles.size() == 2:
		var tile_a: Dictionary = tiles[0]
		var tile_b: Dictionary = tiles[1]
		t.eq(tile_b["origin"], Vector2(10, 0), "second tile origin")
		var links: Array = Stitching.stitch(tile_a, tile_b, 0.05)
		t.check(links.size() > 0, "adjacent tiles share portals")
		var graph: Dictionary = Stitching.build_graph(tiles, 0.05)
		var path: PackedVector2Array = Stitching.find_path(graph, Vector2(2.0, 8.0), Vector2(18.0, 8.0))
		t.check(path.size() >= 2, "path crosses the tile border")
		t.check(_covered(tile_a, 9.9, 8.0) and _covered(tile_b, 10.1, 8.0), "walkable space continues across the border")

	t.current = "navigation mesh"
	var nm: NavigationMesh = baker.to_navigation_mesh(holed)
	t.check(nm.vertices.size() >= 3, "navigation mesh has vertices")
	t.eq(nm.get_polygon_count(), (holed["polygons"] as Array).size(), "navigation mesh polygon count")
	var valid := true
	for i in nm.get_polygon_count():
		for idx in nm.get_polygon(i):
			if idx < 0 or idx >= nm.vertices.size():
				valid = false
	t.check(valid, "navigation mesh indices valid")
	var empty_nm: NavigationMesh = baker.to_navigation_mesh({"polygons": [], "heights": []})
	t.eq(empty_nm.get_polygon_count(), 0, "empty tile converts to an empty mesh")
