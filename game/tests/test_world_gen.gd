extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func run(t) -> void:
	t.current = "determinism"
	var a := WorldGen.new(42)
	var b := WorldGen.new(42)
	var c := WorldGen.new(43)
	var same := true
	var different := false
	for i in 200:
		var x := float(i) * 13.7 - 900.0
		var z := float(i) * -9.1 + 400.0
		if a.height_at(x, z) != b.height_at(x, z):
			same = false
		if absf(a.height_at(x, z) - c.height_at(x, z)) > 0.5:
			different = true
	t.check(same, "the same seed gives the same terrain")
	t.check(different, "a different seed gives different terrain")
	var chunk_a := a.chunk(Vector2i(5, -3))
	var chunk_b := b.chunk(Vector2i(5, -3))
	t.eq(chunk_a["nodes"].size(), chunk_b["nodes"].size(), "same seed, same number of nodes")
	var identical := true
	for i in chunk_a["nodes"].size():
		if chunk_a["nodes"][i] != chunk_b["nodes"][i]:
			identical = false
	t.check(identical, "same seed, identical chunk content")

	t.current = "hub"
	for angle in 8:
		var p := Vector2.from_angle(angle * 0.785) * 30.0
		t.near(a.height_at(p.x, p.y), WorldGen.HUB_HEIGHT, 0.01, "the hub is level")
		t.check(a.is_safe(p.x, p.y), "inside the hub is safe")
		t.check(not a.is_water(p.x, p.y), "the hub is dry land")
	t.check(not a.is_safe(80.0, 0.0), "outside the hub is not safe")
	for cx in range(-1, 1):
		for cz in range(-1, 1):
			var hub_chunk := a.chunk(Vector2i(cx, cz))
			t.eq(hub_chunk["spawns"].size(), 0, "no zombies spawn in the hub chunks")
			t.check(not hub_chunk["ruin"], "no ruin in the hub")
			for node in hub_chunk["nodes"]:
				t.check(Vector2(node["x"], node["z"]).length() > Defs.HUB_SAFE_RADIUS, "nothing is gathered inside the hub")

	t.current = "zones"
	t.eq(Defs.zone_index_for_distance(10.0), 0, "close is green")
	t.eq(Defs.zone_index_for_distance(300.0), 1, "300 m is yellow")
	t.eq(Defs.zone_index_for_distance(800.0), 2, "800 m is red")
	t.eq(Defs.zone_index_for_distance(5000.0), 3, "far is black")
	t.eq(WorldGen.tier_for_zone(0), 1, "green gives tier 1")
	t.eq(WorldGen.tier_for_zone(3), 4, "black gives tier 4")

	t.current = "chunk content"
	var total_nodes := 0
	var tiers_seen: Dictionary = {}
	var kinds_seen: Dictionary = {}
	var ruins := 0
	var zombies := 0
	var min_spacing := 1000.0
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var data := a.chunk(Vector2i(cx, cz))
			total_nodes += data["nodes"].size()
			ruins += 1 if data["ruin"] else 0
			zombies += data["spawns"].size()
			for node in data["nodes"]:
				tiers_seen[node["tier"]] = true
				kinds_seen[node["kind"]] = true
				t.check(node["tier"] >= 1 and node["tier"] <= Defs.MAX_TIER, "node tier in range")
				t.check(not a.is_water(node["x"], node["z"]), "nodes are not placed in water")
				t.near(node["y"], a.height_at(node["x"], node["z"]), 0.001, "node height matches the terrain")
				# A node belongs to its own chunk.
				t.eq(WorldGen.cell_of(node["x"], node["z"]), Vector2i(cx, cz), "node lies in its chunk")
	t.check(total_nodes > 3000, "the world has plenty to gather (%d)" % total_nodes)
	t.check(tiers_seen.size() >= 3, "several tiers exist near the hub (%d)" % tiers_seen.size())
	t.check(kinds_seen.has("tree") and kinds_seen.has("rock") and kinds_seen.has("bush"), "trees, rocks and bushes exist")
	t.check(ruins > 8, "ruins exist (%d)" % ruins)
	t.check(zombies > 100, "zombies exist (%d)" % zombies)

	t.current = "ids"
	var ids: Dictionary = {}
	var duplicate := false
	for cx in range(-6, 7):
		for cz in range(-6, 7):
			var data := a.chunk(Vector2i(cx, cz))
			for group in ["nodes", "crates", "spawns"]:
				for entity in data[group]:
					if ids.has(entity["id"]):
						duplicate = true
					ids[entity["id"]] = true
	t.check(not duplicate, "entity ids are unique across chunks")

	t.current = "biomes"
	var seen: Dictionary = {}
	for i in 4000:
		seen[a.biome_at(randf_range(-2500.0, 2500.0), randf_range(-2500.0, 2500.0))] = true
	t.check(seen.has("water") and seen.has("plains") and seen.has("forest"), "water, plains and forest exist: %s" % str(seen.keys()))

	t.current = "blockers"
	var data := a.chunk(Vector2i(8, 8))
	for node in data["nodes"]:
		if node["blocks"]:
			var found := a.blockers_near(node["x"], node["z"], 0.5)
			var contains := false
			for f in found:
				if f["id"] == node["id"]:
					contains = true
			t.check(contains, "a blocking node is found near itself")
			break
