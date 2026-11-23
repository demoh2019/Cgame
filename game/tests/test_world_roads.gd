extends RefCounted
## Roads between the places and the landmarks in the empty regions.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const WorldRoads = preload("res://scripts/shared/world_roads.gd")


## Brute-force reference retained in tests so nearest-K optimization cannot
## silently change link topology or the deterministic equal-distance tie break.
static func _reference_links(places: Array, max_link: float, regular: int, hub: int) -> Dictionary:
	var links: Dictionary = {}
	for i in places.size():
		var wanted: int = hub if i == 0 else regular
		var nearest: Array = []
		var point := Vector2(float(places[i]["x"]), float(places[i]["z"]))
		for j in places.size():
			if i == j:
				continue
			var other := Vector2(float(places[j]["x"]), float(places[j]["z"]))
			var distance: float = point.distance_to(other)
			if distance <= max_link:
				nearest.append([distance, j])
		nearest.sort_custom(func(a, b) -> bool:
			return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for k in mini(wanted, nearest.size()):
			var target: int = int(nearest[k][1])
			links[Vector2i(mini(i, target), maxi(i, target))] = true
	return links


func run(t) -> void:
	var world := WorldGen.new(1337)
	t.current = "procedural road nearest-neighbor graph"
	var sample_places: Array = [
		{"x": 0.0, "z": 0.0},
		{"x": 2.0, "z": 0.0},
		{"x": -2.0, "z": 0.0},
		{"x": 0.0, "z": 4.0},
		{"x": 50.0, "z": 50.0},
	]
	var scalar_links: Dictionary = WorldRoads.compute_links(sample_places, 4.1, 1, 2, true)
	var generated_links: Dictionary = WorldRoads.compute_links(sample_places, 4.1, 1, 2)
	t.eq(generated_links, scalar_links, "native and GDScript graph topology agree")
	t.check(generated_links.has(Vector2i(0, 1)), "first equidistant neighbor is selected")
	t.check(generated_links.has(Vector2i(0, 2)), "second equidistant neighbor is selected")
	t.check(generated_links.has(Vector2i(0, 3)), "a point on the radius boundary connects")
	t.eq(generated_links.size(), 3, "distant sites do not create out-of-range road edges")
	t.eq(WorldRoads.compute_links(sample_places, 0.0, 2, 4).size(), 0, "zero radius excludes separated sites")
	var stress_places: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 823913
	for i in 96:
		stress_places.append({"x": rng.randi_range(-500, 500), "z": rng.randi_range(-500, 500)})
	stress_places.append(stress_places[0].duplicate()) # Colocated sites exercise equal-distance ties.
	for max_distance in [0.0, 100.0, 650.0, 1100.0]:
		for neighbors in [0, 1, 2, 4, 8]:
			var reference: Dictionary = _reference_links(stress_places, float(max_distance), neighbors, neighbors + 1)
			var optimized: Dictionary = WorldRoads.compute_links(stress_places,
					float(max_distance), neighbors, neighbors + 1, true)
			t.eq(optimized, reference, "bounded scalar links preserve complete graph ordering and ties")
	t.eq(WorldRoads.compute_links([], 720.0, 2, 4, true).size(), 0, "empty graph needs no links")
	if Geometry2D.has_method("get_nearest_neighbors"):
		var points := PackedVector2Array([Vector2.ZERO, Vector2(2.0, 0.0),
				Vector2(-2.0, 0.0), Vector2(0.0, 4.0)])
		var nearest: Array = Geometry2D.call("get_nearest_neighbors", points, 2, 4.1)
		t.eq(nearest.size(), 4, "native API returns one index list per point")
		t.eq(PackedInt32Array(nearest[0]), PackedInt32Array([1, 2]), "nearest point ordering is stable")

	# Compare the full generated road graph from actual island locations.
	var region_places: Array = [{"x": 0.0, "z": 0.0}]
	for rx in range(-3, 4):
		for rz in range(-3, 4):
			for site in world.poi.sites_in_region(rx, rz):
				if WorldRoads.LINKED_KINDS.has(str(site["kind"])):
					region_places.append({"x": float(site["x"]), "z": float(site["z"])})
	var expected_links: Dictionary = WorldRoads.compute_links(region_places, WorldRoads.MAX_LINK,
			WorldRoads.NEIGHBOURS, WorldRoads.HUB_LINKS, true)
	var real_links: Dictionary = WorldRoads.compute_links(region_places)
	t.eq(real_links, expected_links, "island road graph matches stock-Godot fallback")
	t.check(region_places.size() >= 10, "road graph parity covers multiple inhabited regions")

	t.current = "roads"
	var roads: Array = world.roads.all_roads()
	t.check(roads.size() > 150, "many roads join the island (%d)" % roads.size())
	var from_hub := 0
	for road in roads:
		var points: PackedVector2Array = road["points"]
		t.check(points.size() >= 3, "a road has a course")
		if road["from"] == "Hub" or road["to"] == "Hub":
			from_hub += 1
			t.check(points[0].length() >= WorldRoads.HUB_START - 0.5, "hub roads start at the edge of the plaza")
		for i in points.size() - 1:
			t.check(points[i].distance_to(points[i + 1]) < WorldRoads.STEP * 2.5, "the points of a road are close together")
	t.check(from_hub >= WorldRoads.HUB_LINKS, "several roads leave the hub (%d)" % from_hub)
	var signs := 0
	var pieces := 0
	for cx in range(-20, 21):
		for cz in range(-20, 21):
			for sign in world.roads.signs_in_cell(Vector2i(cx, cz)):
				signs += 1
				t.eq(Vector2i(floori(float(sign["x"]) / Defs.CHUNK_SIZE), floori(float(sign["z"]) / Defs.CHUNK_SIZE)), Vector2i(cx, cz), "a signpost is listed in its own chunk")
				t.check(str(sign["to"]) != "" and int(sign["metres"]) > 0, "a signpost names a place and a distance")
				t.check(not world.is_water(float(sign["x"]), float(sign["z"])), "a signpost stands on land")
			pieces += world.roads.pieces_in_cell(Vector2i(cx, cz)).size()
	t.check(signs > 100 and pieces > 500, "signposts (%d) and road pieces (%d) are spread over the chunks" % [signs, pieces])
	# Authoritative road speed/grip uses the new native geometry API when available,
	# while stock Godot continues to use the original scalar implementation.
	t.current = "road coverage parity"
	var empty_road_cells := 0
	for cx in range(-13, 14, 2):
		for cz in range(-13, 14, 2):
			var cell := Vector2i(cx, cz)
			if not world.roads.pieces_in_cell(cell).is_empty():
				continue
			var point := Vector2(cell) * Defs.CHUNK_SIZE + Vector2.ONE * 17.0
			t.eq(world.roads.coverage_at(point.x, point.y), 0.0,
					"roadless cells skip terrain work and have zero road coverage")
			empty_road_cells += 1
	t.check(empty_road_cells > 0, "unoccupied road cells exist on the island")
	var sample_count := 0
	for cell_x in range(-8, 9):
		for cell_z in range(-8, 9):
			var cell := Vector2i(cell_x, cell_z)
			var segments: Array = world.roads.pieces_in_cell(cell)
			if segments.is_empty():
				continue
			var a: Vector2 = segments[0][0]
			var b: Vector2 = segments[0][1]
			for offset in [Vector2.ZERO, Vector2(0.6, -0.8), Vector2(5.0, 2.0)]:
				var point: Vector2 = (a + b) * 0.5 + offset
				if world.is_water(point.x, point.y):
					continue
				var reference: float = WorldRoads.coverage_on_segments(point, segments)
				t.near(world.roads.coverage_at(point.x, point.y), reference, 0.00011, "native road grip matches scalar")
				t.near(world.roads.coverage_on_land(point.x, point.y), reference, 0.00011,
						"dry-land generation skips water tests without changing road clearance")
				sample_count += 1
			if sample_count >= 100:
				break
		if sample_count >= 100:
			break
	t.check(sample_count >= 15, "road grip parity checks cover inhabited cells")
	if Geometry2D.has_method("get_closest_point_on_segments"):
		var endpoints := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(2, 2), Vector2(2, 2)])
		var result: Dictionary = Geometry2D.call("get_closest_point_on_segments", Vector2(4, 3), endpoints)
		t.eq(int(result.get("segment_index", -1)), 0, "nearest segment index is stable")
		t.near(float(result.get("distance", -1.0)), 3.0, 0.00001, "nearest segment distance")
		t.near(float(result.get("t", -1.0)), 0.4, 0.00001, "nearest segment interpolation")
		t.check(Geometry2D.call("get_closest_point_on_segments", Vector2.ZERO, PackedVector2Array()).is_empty(), "empty segments return no hit")

	t.current = "road mask native rasterization parity"
	var mask_segments: Array = [
		[Vector2(1.0, 2.5), Vector2(13.0, 2.5)],
		[Vector2(6.5, -4.0), Vector2(6.5, 12.0)],
		[Vector2(11.5, 9.5), Vector2(11.5, 9.5)],
		[Vector2(-8.0, 8.5), Vector2(4.0, 8.5)]
	]
	var scalar_mask: PackedByteArray = WorldRoads.rasterize_mask(mask_segments, Vector2.ZERO, 16, 2.1, 1.2, true)
	var render_mask: PackedByteArray = WorldRoads.rasterize_mask(mask_segments, Vector2.ZERO, 16, 2.1, 1.2)
	t.eq(render_mask.size(), 16 * 16, "native/scalar road masks have the expected texture length")
	t.eq(int(render_mask[2 * 16 + 4]), 255, "road center fills its pixel")
	t.eq(int(render_mask[9 * 16 + 11]), 255, "zero-length segment paints a round cap")
	var maximum_difference := 0
	for i in scalar_mask.size():
		maximum_difference = maxi(maximum_difference, absi(int(render_mask[i]) - int(scalar_mask[i])))
	t.check(maximum_difference <= 1, "native road mask agrees with scalar rasterization within L8 quantization")
	var empty_mask: PackedByteArray = WorldRoads.rasterize_mask([], Vector2.ZERO, 8)
	t.eq(empty_mask.size(), 64, "empty segment input returns a blank mask")
	t.check(empty_mask.count(0) == 64, "empty segment mask remains transparent")

	# Real road cells verify world-to-local offset and boundary clipping.
	var checked_cells := 0
	for cx in range(-5, 6):
		for cz in range(-5, 6):
			var test_cell := Vector2i(cx, cz)
			var local_pieces: Array = world.roads.pieces_in_cell(test_cell)
			if local_pieces.is_empty():
				continue
			var local_origin: Vector2 = Vector2(test_cell) * Defs.CHUNK_SIZE
			var scalar: PackedByteArray = WorldRoads.rasterize_mask(local_pieces, local_origin, 16, 2.1, 1.2, true)
			var rendered: PackedByteArray = WorldRoads.rasterize_mask(local_pieces, local_origin, 16, 2.1, 1.2)
			var max_error := 0
			for j in scalar.size():
				max_error = maxi(max_error, absi(int(scalar[j]) - int(rendered[j])))
			t.check(max_error <= 1, "chunk road mask native/fallback parity")
			checked_cells += 1
			if checked_cells >= 6:
				break
		if checked_cells >= 6:
			break
	t.check(checked_cells >= 3, "real road mask parity checks sampled road cells")

	var again := WorldGen.new(1337)
	t.eq(again.roads.all_roads().size(), roads.size(), "the same seed lays the same roads")

	t.current = "landmarks"
	var titles: Dictionary = {}
	for rx in range(-13, 13):
		for rz in range(-13, 13):
			for site in world.poi.sites_in_region(rx, rz):
				if site["kind"] != "landmark":
					continue
				titles[site["title"]] = true
				t.check(str(site["display"]).ends_with(str(site["title"])), "a landmark is named after what it is")
				var content: Dictionary = world.poi.contents(site)
				var monuments := 0
				for item in content["structures"]:
					if item["kind"] == "monument":
						monuments += 1
						t.check(item["variant"] >= 0 and item["variant"] < WorldPoi.MONUMENT_RADII.size(), "a monument variant in range")
						t.near(float(item["radius"]), float(WorldPoi.MONUMENT_RADII[item["variant"]]), 0.0001, "a monument blocks with its own radius")
				if site["title"] != "Battlefield":
					t.check(monuments >= 1, "%s has its monument" % site["title"])
	for title in ["Stone Circle", "Crystal Grove", "Great Tree", "Old Shrine", "Battlefield"]:
		t.check(titles.has(title), "the island has a %s" % title)
