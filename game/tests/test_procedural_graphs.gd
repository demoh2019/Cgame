extends RefCounted
## Procedural caves, buildings/settlements and road graphs.

const Caves = preload("res://scripts/shared/procedural_caves.gd")
const Buildings = preload("res://scripts/shared/procedural_buildings.gd")
const Roads = preload("res://scripts/shared/road_network.gd")


func run(t) -> void:
	_caves(t)
	_buildings(t)
	_settlement(t)
	_roads(t)


func _caves(t) -> void:
	t.current = "caves"
	var w: int = 64
	var h: int = 48
	var a: PackedByteArray = Caves.generate(w, h, 1234)
	var b: PackedByteArray = Caves.generate(w, h, 1234)
	var c: PackedByteArray = Caves.generate(w, h, 99)
	t.check(a == b, "same seed gives identical cave")
	t.check(a != c, "different seed gives a different cave")
	var open: int = 0
	for v in a:
		if v == 0:
			open += 1
	t.check(open > 200, "cave has open floor")
	t.eq(Caves.regions(a, w, h).size(), 1, "cave is a single connected region")
	for seed in [1, 2, 3, 4, 5, 6]:
		var g: PackedByteArray = Caves.generate(w, h, seed, 0.55, 3)
		t.eq(Caves.regions(g, w, h).size(), 1, "dense cave connected for seed %d" % seed)
	var border_rock: bool = true
	for x in w:
		if a[x] != 1 or a[(h - 1) * w + x] != 1:
			border_rock = false
	t.check(border_rock, "border stays rock")
	# Hand-made grid: two rooms split by rock.
	var tiny := PackedByteArray()
	tiny.resize(10 * 5)
	tiny.fill(1)
	for y in range(1, 4):
		for x in [1, 2, 6, 7, 8]:
			tiny[y * 10 + x] = 0
	t.eq(Caves.regions(tiny, 10, 5).size(), 2, "regions finds two rooms")
	t.eq(Caves.chambers(tiny, 10, 5, 8).size(), 1, "chambers filters by size")
	t.eq(Caves.chambers(tiny, 10, 5, 1).size(), 2, "chambers returns both rooms")
	var ch: Array = Caves.chambers(tiny, 10, 5, 8)
	var p: Vector2 = ch[0]
	t.eq(tiny[int(p.y) * 10 + int(p.x)], 0, "chamber centre is on open floor")
	var real: Array = Caves.chambers(a, w, h, 20)
	t.check(real.size() >= 1, "generated cave has a chamber")


func _buildings(t) -> void:
	t.current = "buildings"
	var fp := Vector2i(16, 12)
	var b1: Dictionary = Buildings.building(7, fp, 3)
	var b2: Dictionary = Buildings.building(7, fp, 3)
	t.check(b1 == b2, "same seed gives identical building")
	var rooms: Array = b1["rooms"]
	t.check(rooms.size() >= 3, "building has several rooms")
	for f in 3:
		var floor_rects: Array = []
		var area: int = 0
		var min_ok: bool = true
		for rm in rooms:
			var rd: Dictionary = rm
			if int(rd["floor"]) != f:
				continue
			var r: Rect2i = rd["rect"]
			floor_rects.append(r)
			area += r.get_area()
			if r.size.x < 3 or r.size.y < 3:
				min_ok = false
			t.check(Rect2i(Vector2i.ZERO, fp).encloses(r), "room inside footprint")
		t.eq(area, fp.x * fp.y, "rooms cover footprint on floor %d" % f)
		t.check(min_ok, "rooms at least 3x3 on floor %d" % f)
		var overlap: bool = false
		for i in floor_rects.size():
			for j in range(i + 1, floor_rects.size()):
				var ra: Rect2i = floor_rects[i]
				var rb: Rect2i = floor_rects[j]
				if ra.intersects(rb):
					overlap = true
		t.check(not overlap, "rooms do not overlap on floor %d" % f)
		# Reachability through doors.
		var ids: Array = []
		for rm in rooms:
			var rd2: Dictionary = rm
			if int(rd2["floor"]) == f:
				ids.append(int(rd2["id"]))
		var seen: Dictionary = {ids[0]: true}
		var changed: bool = true
		while changed:
			changed = false
			for dr in b1["doors"]:
				var dd: Dictionary = dr
				if int(dd["floor"]) != f:
					continue
				var da: int = dd["a"]
				var db: int = dd["b"]
				if seen.has(da) != seen.has(db):
					seen[da] = true
					seen[db] = true
					changed = true
		t.eq(seen.size(), ids.size(), "every room reachable via doors on floor %d" % f)
	var stairs: Array = b1["stairs"]
	t.eq(stairs.size(), 2, "stairs between each pair of floors")
	for s in stairs:
		var sd: Dictionary = s
		t.check(int(sd["room_to"]) >= 0, "stairs land in a room above")
	t.eq((Buildings.building(7, fp, 1)["stairs"] as Array).size(), 0, "single floor has no stairs")
	var windows: Array = b1["windows"]
	t.check(windows.size() > 0, "building has windows")
	var wall_ok: bool = true
	for wd in windows:
		var wdict: Dictionary = wd
		var cell: Vector2i = wdict["cell"]
		if cell.x != 0 and cell.y != 0 and cell.x != fp.x - 1 and cell.y != fp.y - 1:
			wall_ok = false
	t.check(wall_ok, "windows only on exterior walls")
	var tiny: Dictionary = Buildings.building(1, Vector2i(2, 2), 1)
	t.eq((tiny["rooms"] as Array).size(), 1, "tiny footprint is one room")
	t.current = "hostile POI dimensions cannot create unbounded room graphs"
	var oversized: Dictionary = Buildings.building(77,
		Vector2i(1000000, 1000000), 1000000)
	t.eq(oversized["footprint"], Vector2i(
		Buildings.MAX_BUILDING_SIDE, Buildings.MAX_BUILDING_SIDE),
		"oversized footprint is clamped to a predictable maximum")
	t.eq(int(oversized["floors"]), Buildings.MAX_BUILDING_FLOORS,
		"floor count is clamped before per-floor layout")
	var negative: Dictionary = Buildings.building(77, Vector2i(-100, 0), -8)
	t.eq(negative["footprint"], Vector2i(3, 3),
		"negative dimensions recover to the minimum legal room")
	t.eq(int(negative["floors"]), 1, "invalid floor count recovers to one")
	t.check(negative == Buildings.building(77, Vector2i(3, 3), 1),
		"clamped invalid geometry remains deterministic")


func _settlement(t) -> void:
	t.current = "settlement"
	var center := Vector2(100.0, -50.0)
	var radius: float = 80.0
	var s1: Array = Buildings.settlement(5, center, radius, 12)
	var s2: Array = Buildings.settlement(5, center, radius, 12)
	t.check(s1 == s2, "same seed gives identical settlement")
	var plaza: Dictionary = s1[0]
	t.eq(plaza["kind"], "plaza", "first entry is the plaza")
	t.check((plaza["center"] as Vector2).is_equal_approx(center), "plaza at centre")
	var lots: Array = s1.slice(1)
	t.check(lots.size() >= 3 and lots.size() <= 12, "lot count within bounds (%d)" % lots.size())
	var plaza_r: float = plaza["radius"]
	var inside: bool = true
	var clear_of_plaza: bool = true
	var overlap: bool = false
	for i in lots.size():
		var li: Dictionary = lots[i]
		var ri: Rect2 = li["rect"]
		for corner in [ri.position, ri.end, Vector2(ri.position.x, ri.end.y), Vector2(ri.end.x, ri.position.y)]:
			var cp: Vector2 = corner
			if cp.distance_to(center) > radius:
				inside = false
		if ri.get_center().distance_to(center) < plaza_r:
			clear_of_plaza = false
		for j in range(i + 1, lots.size()):
			var lj: Dictionary = lots[j]
			var rj: Rect2 = lj["rect"]
			if ri.intersects(rj):
				overlap = true
	t.check(inside, "lots lie within the radius")
	t.check(clear_of_plaza, "lots avoid the plaza")
	t.check(not overlap, "lots do not overlap")
	t.eq((Buildings.settlement(1, center, radius, 0) as Array).size(), 1, "zero count gives plaza only")
	t.current = "settlement generation rejects malformed geometry and caps work"
	t.eq(Buildings.settlement(1, Vector2(INF, 0.0), radius, 10), [],
		"nonfinite settlement center is rejected")
	t.eq(Buildings.settlement(1, center, NAN, 10), [],
		"NaN radius is rejected before Poisson sampling")
	t.eq(Buildings.settlement(1, center, INF, 10), [],
		"infinite radius cannot create invalid lot rectangles")
	t.eq(Buildings.settlement(1, center, Buildings.MAX_SETTLEMENT_RADIUS + 1.0, 10), [],
		"unsupported world-scale radius is rejected")
	var bounded: Array = Buildings.settlement(818, center, radius, 1000000)
	t.check(bounded.size() <= Buildings.MAX_SETTLEMENT_LOTS + 1,
		"lot count is bounded even when a POI requests one million")
	t.check(bounded == Buildings.settlement(818, center, radius, 1000000),
		"bounded settlement stays deterministic")
	var invalid_count: Array = Buildings.settlement(1, center, radius, -1)
	t.eq(invalid_count, [], "negative lot requests do not create phantom plazas")


func _roads(t) -> void:
	t.current = "roads"
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var sites := PackedVector2Array()
	for i in 25:
		sites.append(Vector2(rng.randf_range(0.0, 500.0), rng.randf_range(0.0, 500.0)))
	var n: int = sites.size()
	var e0: Array = Roads.connect_sites(sites, 0.0, 1)
	t.eq(e0.size(), n - 1, "MST has n-1 edges")
	t.check(_components(n, e0) == 1, "MST connects all sites")
	var e1: Array = Roads.connect_sites(sites, 0.3, 1)
	var e2: Array = Roads.connect_sites(sites, 0.3, 1)
	t.check(e1 == e2, "road graph deterministic")
	t.check(e1.size() > n - 1, "extra edges add loops")
	t.check(_components(n, e1.slice(0, n - 1)) == 1 and _acyclic(n, e1.slice(0, n - 1)), "first n-1 edges form an acyclic tree")
	t.check(_components(n, e1) == 1, "graph with loops stays connected")
	var good: bool = true
	for e in e1:
		var ed: Dictionary = e
		if absf(float(ed["length"]) - sites[ed["a"]].distance_to(sites[ed["b"]])) > 0.001:
			good = false
	t.check(good, "edge lengths match geometry")
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(30, 0)])
	var le: Array = Roads.connect_sites(line, 0.0, 0)
	t.eq(le.size(), 3, "collinear sites still connect")
	t.eq((Roads.connect_sites(PackedVector2Array([Vector2.ZERO, Vector2(5, 5)])) as Array).size(), 1, "two sites give one road")
	t.eq((Roads.connect_sites(PackedVector2Array([Vector2.ZERO])) as Array).size(), 0, "one site gives no roads")
	var flat := func(_p: Vector2) -> float: return 0.0
	var hill := func(p: Vector2) -> float: return p.x * 0.5
	var a := Vector2(0, 0)
	var b := Vector2(100, 0)
	t.near(Roads.route_cost(a, b, flat, 5.0), 100.0, 0.01, "flat ground costs its length")
	var steep: float = Roads.route_cost(a, b, hill, 5.0)
	t.check(steep > 100.0 * 1.5, "slopes are penalised")
	t.check(Roads.route_cost(a, b, hill, 10.0) > steep, "bigger penalty costs more")
	t.near(Roads.route_cost(a, a, hill, 5.0), 0.0, 0.0001, "zero-length route is free")


func _find(parent: PackedInt32Array, i: int) -> int:
	var r: int = i
	while parent[r] != r:
		r = parent[r]
	return r


func _components(n: int, edges: Array) -> int:
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var comps: int = n
	for e in edges:
		var ed: Dictionary = e
		var ra: int = _find(parent, ed["a"])
		var rb: int = _find(parent, ed["b"])
		if ra != rb:
			parent[ra] = rb
			comps -= 1
	return comps


func _acyclic(n: int, edges: Array) -> bool:
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	for e in edges:
		var ed: Dictionary = e
		var ra: int = _find(parent, ed["a"])
		var rb: int = _find(parent, ed["b"])
		if ra == rb:
			return false
		parent[ra] = rb
	return true
