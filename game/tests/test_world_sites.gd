extends RefCounted
## The big populated world: an island with villages, camps, forts, ruined cities and more, all from the seed.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const CityLayout = preload("res://scripts/shared/city_layout.gd")


func _all_sites(world, radius_regions: int = 13) -> Array:
	var sites: Array = []
	for rx in range(-radius_regions, radius_regions + 1):
		for rz in range(-radius_regions, radius_regions + 1):
			sites.append_array(world.poi.sites_in_region(rx, rz))
	return sites


func run(t) -> void:
	_island(t)
	_sites(t)
	_city_layouts(t)
	_contents(t)
	_chunks(t)
	_stations(t)
	_determinism(t)
	_cache_bounds(t)


func _island(t) -> void:
	t.current = "the island"
	var world := WorldGen.new(1337)
	t.check(WorldGen.WORLD_RADIUS >= 3000.0, "the world is at least 6 km across")
	for angle in 12:
		var edge := Vector2.from_angle(float(angle) * TAU / 12.0) * (WorldGen.WORLD_RADIUS + 20.0)
		t.check(world.is_water(edge.x, edge.y), "the sea closes the world at the edge (angle %d)" % angle)
	var land_samples := 0
	for i in 400:
		var p := Vector2.from_angle(float(i) * 2.399) * (80.0 + float(i) * 6.0)
		if not world.is_water(p.x, p.y):
			land_samples += 1
	t.check(land_samples > 150, "a good part of the island is land (%d of 400)" % land_samples)
	t.check(world.height_at(0.0, 0.0) == WorldGen.HUB_HEIGHT, "the hub is still level")


func _sites(t) -> void:
	t.current = "sites"
	var world := WorldGen.new(1337)
	var sites := _all_sites(world)
	t.check(sites.size() >= 150, "the island holds many sites (%d)" % sites.size())
	var kinds: Dictionary = {}
	var ids: Dictionary = {}
	var names: Dictionary = {}
	for site in sites:
		kinds[site["kind"]] = int(kinds.get(site["kind"], 0)) + 1
		t.check(not ids.has(site["id"]), "site ids are unique")
		ids[site["id"]] = true
		names[site["display"]] = true
		var p := Vector2(float(site["x"]), float(site["z"]))
		t.check(p.length() >= WorldPoi.MIN_HUB_DISTANCE, "a site keeps away from the hub")
		t.check(p.length() < WorldGen.WORLD_RADIUS - 200.0, "a site stays well inside the island")
		t.check(not world.is_water(p.x, p.y), "a site stands on dry land")
		t.check(world.height_at(p.x, p.y) > Defs.WATER_LEVEL, "and above the water")
		t.check(WorldPoi.KINDS.has(site["kind"]), "a known kind")
		t.check(str(site["name"]).length() >= 5, "every site has a name")
		t.eq(int(site["zone"]), world.zone_at(p.x, p.y), "the zone is the one of its position")
	for kind in ["village", "farm", "camp", "depot", "outpost", "tower", "mine", "city", "bunker", "lighthouse", "dock"]:
		t.check(int(kinds.get(kind, 0)) >= 1 or kind == "mine", "the island has a %s (%d)" % [kind, int(kinds.get(kind, 0))])
	t.check(int(kinds.get("village", 0)) >= 10, "at least ten villages where people live (%d)" % int(kinds.get("village", 0)))
	t.check(int(kinds.get("city", 0)) >= 10, "and ruined cities to loot (%d)" % int(kinds.get("city", 0)))
	t.check(names.size() >= sites.size() * 0.8, "names are varied (%d different for %d sites)" % [names.size(), sites.size()])
	# Distance rules: living places are not all in one band.
	var near := 0
	var far := 0
	for site in sites:
		if str(site["kind"]) == "village" or str(site["kind"]) == "outpost":
			if Vector2(float(site["x"]), float(site["z"])).length() < 1050.0:
				near += 1
			else:
				far += 1
	t.check(near >= 3 and far >= 8, "settlements exist both close to the hub (%d) and far away (%d)" % [near, far])


func _city_layouts(t) -> void:
	t.current = "city footprint and street plans"
	var radius := 92.0
	var angle := 0.37
	for layout in CityLayout.TYPES:
		var lots: Array[Dictionary] = CityLayout.building_lots(97321, layout, radius, angle)
		t.check(lots.size() >= 14, "%s creates many buildable lots" % layout)
		t.eq(lots, CityLayout.building_lots(97321, layout, radius, angle), "city lots are deterministic")
		for lot in lots:
			var offset: Vector2 = lot["offset"]
			t.check(CityLayout.contains(offset, layout, radius, angle), "a city lot stays inside its footprint")
			t.check(offset.length() <= radius, "a city lot stays in the surrounding site circle")
		var streets: Array = CityLayout.streets(layout, radius, angle)
		t.check(streets.size() >= 3, "%s has a local road network" % layout)
		var street_index: Dictionary = CityLayout.index_streets(streets, 12.0, 8.0)
		var segments: PackedVector2Array = street_index["segments"]
		t.check(segments.size() >= 6, "the city street index contains segments")
		for xi in range(-3, 4):
			for yi in range(-3, 4):
				var probe: Vector2 = Vector2(float(xi), float(yi)).rotated(angle) * radius * 0.17
				for clearance in [1.0, 3.1, 6.82, 10.0]:
					var scalar_blocked: bool = CityLayout.street_distance(probe, streets) < float(clearance)
					t.eq(CityLayout.street_blocked(probe, float(clearance), street_index), scalar_blocked,
							"spatial street index matches scalar clearance, including its large-radius fallback")
		var safe_lots := 0
		for lot in lots:
			var offset: Vector2 = lot["offset"]
			if CityLayout.street_distance(offset, streets) >= 6.82:
				safe_lots += 1
		t.check(safe_lots >= 14, "%s retains enough building lots clear of streets (%d)" % [layout, safe_lots])
		for street in streets:
			var path: PackedVector2Array = street
			t.check(path.size() >= 3, "city streets have enough points for road painting")
			for point in path:
				t.check(point.length() <= radius, "city roads stay in the surrounding site circle")
				t.check(CityLayout.contains(point, layout, radius, angle), "city streets stay within their own footprint")
		var entrance: Vector2 = CityLayout.entrance_offset(layout, radius, angle, Vector2.RIGHT)
		t.eq(CityLayout.entrance_on_paths(streets, Vector2.RIGHT), entrance,
				"road entrances reuse cached street paths without changing geometry")
		t.check(CityLayout.contains(entrance, layout, radius, angle), "the city entrance is inside the footprint")
		var terminal_found := false
		for street in streets:
			var path: PackedVector2Array = street
			if entrance.distance_to(path[0]) < 0.0001 or entrance.distance_to(path[path.size() - 1]) < 0.0001:
				terminal_found = true
		t.check(terminal_found, "the city entrance is a real street endpoint")
	t.check(CityLayout.contains(Vector2(70.0, 0.0), "radial", radius), "circular cities extend radially")
	t.check(not CityLayout.contains(Vector2(70.0, 0.0), "grid", radius), "square cities have distinct boundaries")
	t.check(not CityLayout.contains(Vector2(0.0, 70.0), "linear", radius), "linear cities remain narrow")
	t.check(CityLayout.contains(Vector2(0.0, -65.0), "triangular", radius), "triangle has a pointed northern district")
	t.check(not CityLayout.contains(Vector2(60.0, -65.0), "triangular", radius), "triangle has sloping edges")
	t.check(not CityLayout.contains(Vector2(38.64, 0.0), "crescent", radius), "crescent has an open eastern bay")
	t.check(CityLayout.contains(Vector2(-65.0, 0.0), "crescent", radius), "crescent keeps its western districts")
	var probe: Array = [PackedVector2Array([Vector2.ZERO, Vector2(10.0, 0.0)])]
	t.near(CityLayout.street_distance(Vector2(5.0, 3.0), probe), 3.0, 0.0001,
			"obstacle clearance measures the nearest road segment")
	t.near(CityLayout.street_distance(Vector2(5.0, 0.0), probe), 0.0, 0.0001,
			"obstacles lying on a street have zero clearance")

	t.current = "street distances match independent scalar geometry after squared fast path"
	var sample_streets: Array = [
		PackedVector2Array([Vector2(-10.0, -4.0), Vector2(5.0, 4.0),
			Vector2(14.0, -3.0)]),
		PackedVector2Array([Vector2(7.0, 2.0), Vector2(7.0, 2.0),
			Vector2(8.0, 12.0)]),
	]
	var sample_rng := RandomNumberGenerator.new()
	sample_rng.seed = 482156
	for sample in 100:
		var point := Vector2(sample_rng.randf_range(-20.0, 20.0),
			sample_rng.randf_range(-20.0, 20.0))
		var scalar_distance: float = INF
		for street in sample_streets:
			var path: PackedVector2Array = street
			for i in path.size() - 1:
				var a: Vector2 = path[i]
				var delta: Vector2 = path[i + 1] - a
				if delta.length_squared() < 0.00001:
					continue
				var fraction: float = clampf((point - a).dot(delta) /
					delta.length_squared(), 0.0, 1.0)
				scalar_distance = minf(scalar_distance,
					point.distance_to(a + delta * fraction))
		t.near(CityLayout.street_distance(point, sample_streets),
			scalar_distance, 0.0001,
			"seeded road clearance agrees with scalar geometry sample %d" % sample)

	var world := WorldGen.new(1337)
	var seen: Dictionary = {}
	var first_city: Dictionary = {}
	var salvage_caches := 0
	for site in _all_sites(world):
		if str(site["kind"]) != "city":
			continue
		var layout: String = str(site["layout"])
		seen[layout] = true
		t.check(CityLayout.TYPES.has(layout), "a generated city has a supported layout")
		if first_city.is_empty():
			first_city = site
		var center := Vector2(float(site["x"]), float(site["z"]))
		var plan: Dictionary = world.poi.city_plan(site)
		t.check(site.has("city_plan"), "a generated city caches its street paths for reuse")
		t.check(not plan.has("index") and not plan.has("lots"),
				"unvisited cities do not retain an obstacle grid or lot candidates")
		var content: Dictionary = world.poi.contents(site)
		var paths: Array = plan["paths"]
		t.check(not plan.has("index") and not plan.has("lots"),
				"populated cities release their transient spatial grid and lot candidates")
		for group in ["structures", "crates", "props", "spawns"]:
			for item in content[group]:
				var offset := Vector2(float(item["x"]), float(item["z"])) - center
				t.check(CityLayout.contains(offset, layout, float(site["radius"]), float(site["layout_rotation"])),
						"all city content respects its shape")
				if group == "crates" and bool(item.get("urban_cache", false)):
					salvage_caches += 1
					t.eq(item["kind"], "crate", "city salvage uses normal lootable crates")
					t.check(not world.is_water(float(item["x"]), float(item["z"])),
							"city salvage stays on dry ground")
				if group != "spawns" and bool(item.get("blocks", true)):
					var clearance: float = CityLayout.street_distance(offset, paths)
					t.check(clearance + 0.001 >= float(item.get("radius", 0.0)) + 3.1,
							"buildings, ruins and loot never block local city roads")
	t.check(seen.size() >= 3, "the island generates multiple city layouts (%s)" % str(seen.keys()))
	t.check(salvage_caches >= 1, "ruined cities contain additional accessible scavenging caches (%d)" % salvage_caches)
	if not first_city.is_empty():
		var city_roads := 0
		for road in world.roads.all_roads():
			if road["from"] == first_city["display"] and road["to"] == first_city["display"]:
				city_roads += 1
		t.check(city_roads >= 3, "the generated city has internal painted streets")
		var terminals: Array[Vector2] = []
		for street in CityLayout.streets(str(first_city["layout"]), float(first_city["radius"]),
				float(first_city["layout_rotation"])):
			var path: PackedVector2Array = street
			terminals.append(path[0])
			terminals.append(path[path.size() - 1])
		var city_links := 0
		var city_center := Vector2(float(first_city["x"]), float(first_city["z"]))
		for road in world.roads.all_roads():
			var entry: Vector2
			if road["from"] == first_city["display"] and road["to"] != first_city["display"]:
				entry = road["points"][0]
			elif road["to"] == first_city["display"] and road["from"] != first_city["display"]:
				var points: PackedVector2Array = road["points"]
				entry = points[points.size() - 1]
			else:
				continue
			city_links += 1
			var nearest: float = INF
			for terminal in terminals:
				nearest = minf(nearest, (entry - city_center).distance_to(terminal))
			t.check(nearest < 0.001, "intercity roads connect directly to a city street endpoint")
		t.check(city_links > 0, "at least one regional road connects to the city")


func _contents(t) -> void:
	t.current = "site contents"
	var world := WorldGen.new(1337)
	var seen_roles: Dictionary = {}
	var total := {"structures": 0, "crates": 0, "spawns": 0, "props": 0, "npcs": 0}
	for site in _all_sites(world, 9):
		var content: Dictionary = world.poi.contents(site)
		var center := Vector2(float(site["x"]), float(site["z"]))
		for group in total:
			total[group] += content[group].size()
		for item in content["structures"]:
			var p := Vector2(float(item["x"]), float(item["z"]))
			t.check(p.distance_to(center) <= float(site["radius"]) + 8.0, "a structure lies inside its site")
			t.check(not world.is_water(p.x, p.y), "a structure is on land")
			t.check(p.length() > Defs.HUB_SAFE_RADIUS, "a structure is outside the hub")
		for item in content["crates"]:
			t.check(Vector2(float(item["x"]), float(item["z"])).distance_to(center) <= float(site["radius"]) + 4.0, "a crate lies inside its site")
		for npc in content["npcs"]:
			seen_roles[npc["role"]] = true
			t.check(WorldPoi.ROLES.has(npc["role"]) and WorldPoi.CHARACTERS.has(npc["model"]), "a known role and character")
			t.check(str(npc["name"]) != "", "an NPC has a name")
		if bool(site["station"]):
			var traders := 0
			for npc in content["npcs"]:
				if npc["role"] == "trader":
					traders += 1
			t.eq(traders, 1, "a settlement with a station has one trader")
			var bench := 0
			for item in content["structures"]:
				if item["kind"] == "workbench":
					bench += 1
			t.eq(bench, 1, "and one workbench")
		else:
			for npc in content["npcs"]:
				t.check(npc["role"] != "trader", "no trader without a workbench")
	t.check(total["structures"] > 400 and total["props"] > 150 and total["npcs"] > 40 and total["crates"] > 150, "the world is full of things: %s" % str(total))
	for role in ["trader", "guard", "villager", "farmer", "sitter", "watch", "fisher"]:
		t.check(seen_roles.has(role), "survivors of every kind exist (%s)" % role)


func _chunks(t) -> void:
	t.current = "chunks with sites"
	var world := WorldGen.new(1337)
	var started := Time.get_ticks_msec()
	var count := 0
	var seen_ids: Dictionary = {}
	var duplicate := false
	var with_props := 0
	for cx in range(-30, 31):
		for cz in range(-30, 31):
			var data: Dictionary = world.chunk(Vector2i(cx, cz))
			count += 1
			for group in ["nodes", "crates", "spawns", "structures"]:
				for item in data[group]:
					if seen_ids.has(item["id"]):
						duplicate = true
					seen_ids[item["id"]] = true
			if not data["props"].is_empty():
				with_props += 1
			for key in ["props", "npcs", "pois"]:
				t.check(data.has(key), "a chunk has %s" % key)
	var per_chunk: float = float(Time.get_ticks_msec() - started) / float(count)
	t.check(not duplicate, "entity ids are unique across %d chunks" % count)
	t.check(per_chunk < 6.0, "a chunk costs %.2f ms to build" % per_chunk)
	t.check(with_props > 5, "chunks carry props (%d)" % with_props)
	# Props block movement through the same collision list.
	for cx in range(-30, 31):
		for cz in range(-30, 31):
			var data: Dictionary = world.chunk(Vector2i(cx, cz))
			if not data["props"].is_empty():
				var prop: Dictionary = data["props"][0]
				var found := false
				for blocker in world.blockers_near(float(prop["x"]), float(prop["z"]), 1.0):
					if blocker.get("x", 0.0) == prop["x"] and blocker.get("z", 0.0) == prop["z"]:
						found = true
				t.check(found, "a prop blocks movement")
				return


func _stations(t) -> void:
	t.current = "settlement stations"
	var world := WorldGen.new(1337)
	var station := {}
	for site in _all_sites(world):
		if bool(site["station"]):
			station = site
			break
	t.check(not station.is_empty(), "a settlement with a station exists")
	var x: float = float(station["station_x"])
	var z: float = float(station["station_z"])
	t.check(world.settlement_station_near(x, z), "standing at the workbench counts")
	t.check(world.settlement_station_near(x + 4.0, z), "within reach counts")
	t.check(not world.settlement_station_near(x + 40.0, z), "far from it does not")
	t.check(not world.settlement_station_near(0.0, 0.0), "the hub is not a settlement station (it has its own)")
	var around: Dictionary = world.poi.site_at(float(station["x"]), float(station["z"]))
	t.eq(around.get("id", -1), station["id"], "site_at finds the site at its center")
	t.check(world.poi.site_at(1000000.0, 0.0).is_empty(), "and nothing in the open sea")
	# The ground under the station is level.
	var low := 1e9
	var high := -1e9
	for i in 8:
		var q := Vector2(x, z) + Vector2.from_angle(float(i) * TAU / 8.0) * 12.0
		low = minf(low, world.height_at(q.x, q.y))
		high = maxf(high, world.height_at(q.x, q.y))
	t.check(high - low < 1.0, "the ground round a station is level (%.2f m)" % (high - low))


func _determinism(t) -> void:
	t.current = "determinism of sites"
	var first := WorldGen.new(4242)
	var second := WorldGen.new(4242)
	var other := WorldGen.new(4243)
	var same := true
	var differs := false
	for rx in range(-6, 7):
		for rz in range(-6, 7):
			var a: Array = first.poi.sites_in_region(rx, rz)
			var b: Array = second.poi.sites_in_region(rx, rz)
			var c: Array = other.poi.sites_in_region(rx, rz)
			same = same and a.size() == b.size()
			if a.size() == 1 and b.size() == 1:
				same = same and a[0]["display"] == b[0]["display"] and a[0]["x"] == b[0]["x"]
			if a.size() != c.size() or (a.size() == 1 and c.size() == 1 and a[0]["x"] != c[0]["x"]):
				differs = true
	t.check(same, "the same seed gives the same sites")
	t.check(differs, "another seed gives other sites")
	# Order of generation does not matter.
	var forward := WorldGen.new(99)
	var backward := WorldGen.new(99)
	var lines_a: Array = []
	var lines_b: Array = []
	for i in range(-5, 6):
		lines_a.append(forward.chunk(Vector2i(i, 3))["structures"].size())
	for i in range(5, -6, -1):
		lines_b.append(backward.chunk(Vector2i(i, 3))["structures"].size())
	lines_b.reverse()
	t.eq(lines_a, lines_b, "chunk contents do not depend on the order they are built in")


func _cache_bounds(t) -> void:
	t.current = "POI region and leveller caches remain bounded during exploration"
	var world := WorldGen.new(90123)
	var original: Array = world.poi.sites_in_region(-2, 3).duplicate(true)
	for index in range(WorldPoi.REGION_CACHE_LIMIT + 32):
		world.poi.sites_in_region(1000 + index, -1000 - index)
	t.check(world.poi._regions.size() <= WorldPoi.REGION_CACHE_LIMIT,
		"visited POI regions never exceed the LRU capacity")
	t.eq(world.poi._region_lru.size(), world.poi._regions.size(),
		"region LRU has exactly one key per cached region")
	t.eq(world.poi.sites_in_region(-2, 3), original,
		"evicted seeded regions rebuild with identical deterministic content")
	for index in range(WorldPoi.LEVELLER_CACHE_LIMIT + 16):
		world.poi.levellers(500 + index, -750 - index)
	t.check(world.poi._leveller_cache.size() <= WorldPoi.LEVELLER_CACHE_LIMIT,
		"terrain leveller records never exceed the LRU capacity")
	t.eq(world.poi._leveller_lru.size(), world.poi._leveller_cache.size(),
		"leveller LRU has exactly one key per cached record")
