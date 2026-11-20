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
