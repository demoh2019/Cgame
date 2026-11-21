extends RefCounted
## Roads between the places and the landmarks in the empty regions.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const WorldRoads = preload("res://scripts/shared/world_roads.gd")


func run(t) -> void:
	t.current = "roads"
	var world := WorldGen.new(1337)
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
