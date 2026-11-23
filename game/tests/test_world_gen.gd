extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const StoneResources = preload("res://scripts/shared/stone_resources.gd")
const DynamicBlockerGrid = preload("res://scripts/shared/dynamic_blocker_grid.gd")


## Exhaustive reference for outdoor procedural collisions. The cached
## broadphase must return the same IDs and ordering as the old group scan.
static func _reference_procedural_blockers(world, x: float, z: float, radius: float) -> Array[int]:
	var ids: Array[int] = []
	var cell_a: Vector2i = WorldGen.cell_of(x - radius, z - radius)
	var cell_b: Vector2i = WorldGen.cell_of(x + radius, z + radius)
	for cx in range(cell_a.x, cell_b.x + 1):
		for cz in range(cell_a.y, cell_b.y + 1):
			var data: Dictionary = world.chunk(Vector2i(cx, cz))
			for group in ["nodes", "crates", "structures", "props"]:
				for item in data[group]:
					if group == "nodes" and world.depleted_blockers.has(item["id"]):
						continue
					if bool(item["blocks"]) and absf(float(item["x"]) - x) < radius + float(item["radius"]) \
							and absf(float(item["z"]) - z) < radius + float(item["radius"]):
						ids.append(int(item["id"]))
	return ids


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
	var loose_pickups := 0
	var modeled_boulders := 0
	var roadside_caches := 0
	var roadside_ambushes := 0
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var data := a.chunk(Vector2i(cx, cz))
			total_nodes += data["nodes"].size()
			ruins += 1 if data["ruin"] else 0
			zombies += data["spawns"].size()
			for hostile in data["spawns"]:
				if not bool(hostile.get("roadside_ambush", false)):
					continue
				roadside_ambushes += 1
				var ambush_at := Vector2(float(hostile["x"]), float(hostile["z"]))
				t.eq(int(hostile["id"]), WorldGen.entity_id(Vector2i(cx, cz),
						WorldGen.ROADSIDE_CACHE_ID_BASE + 1), "roadside ambushers use reserved stable IDs")
				t.eq(WorldGen.cell_of(ambush_at.x, ambush_at.y), Vector2i(cx, cz),
						"ambushers remain within their spawning chunk")
				t.check(not a.is_water(ambush_at.x, ambush_at.y) and not a.is_safe(ambush_at.x, ambush_at.y),
						"ambushers spawn on unsafe dry ground")
				t.check(a.roads.coverage_at(ambush_at.x, ambush_at.y) <= 0.01,
						"ambushers do not block painted roads")
				var near_cache := false
				for crate in data["crates"]:
					if bool(crate.get("roadside_cache", false)):
						var cache_at := Vector2(float(crate["x"]), float(crate["z"]))
						near_cache = ambush_at.distance_to(cache_at) <= 4.01
				t.check(near_cache, "each ambusher protects an accessible roadside cache")
				t.check(str(hostile["type"]) in ["crawler", "stalker"],
						"roadside encounters use the standard infected AI")
			for crate in data["crates"]:
				if not bool(crate.get("roadside_cache", false)):
					continue
				roadside_caches += 1
				var p := Vector2(float(crate["x"]), float(crate["z"]))
				t.eq(crate["kind"], "crate", "roadside supplies use existing lootable crates")
				t.eq(int(crate["id"]), WorldGen.entity_id(Vector2i(cx, cz), WorldGen.ROADSIDE_CACHE_ID_BASE),
						"roadside supplies use reserved stable world IDs")
				t.eq(WorldGen.cell_of(p.x, p.y), Vector2i(cx, cz),
						"roadside supplies stay in their owning chunk")
				t.check(not a.is_water(p.x, p.y), "roadside supplies stay on land")
				t.near(float(crate["y"]), a.height_at(p.x, p.y), 0.001,
						"roadside supplies match terrain height")
				t.check(a.roads.coverage_at(p.x, p.y) <= 0.01, "roadside crates do not block road travel")
				var nearest := INF
				for piece in a.roads.pieces_in_cell(Vector2i(cx, cz)):
					var start: Vector2 = piece[0]
					var end: Vector2 = piece[1]
					var delta: Vector2 = end - start
					if delta.length_squared() <= 0.0001:
						continue
					var fraction: float = clampf((p - start).dot(delta) / delta.length_squared(), 0.0, 1.0)
					nearest = minf(nearest, p.distance_to(start + delta * fraction))
				t.check(nearest <= 9.01, "roadside supply caches are reachable from a nearby road")
			for node in data["nodes"]:
				if node.has("stone_model"):
					var model_index: int = int(node["stone_model"])
					t.check(model_index >= 0 and model_index < StoneResources.MODELS.size(),
						"stone node selects a valid renderable model")
					if str(node["kind"]) == "pebble":
						loose_pickups += 1
						t.eq(int(node["tier"]), 1, "hand-pickable stones are always tier 1")
						t.check(not bool(node["blocks"]), "small stones cannot block movement")
					elif str(node["kind"]) == "rock":
						modeled_boulders += 1
						t.check(bool(node["blocks"]), "minable boulders have collision")
				tiers_seen[node["tier"]] = true
				kinds_seen[node["kind"]] = true
				t.check(node["tier"] >= 1 and node["tier"] <= Defs.MAX_TIER, "node tier in range")
				t.check(not a.is_water(node["x"], node["z"]), "nodes are not placed in water")
				t.near(node["y"], a.height_at(node["x"], node["z"]), 0.001, "node height matches the terrain")
				# A node belongs to its own chunk.
				t.eq(WorldGen.cell_of(node["x"], node["z"]), Vector2i(cx, cz), "node lies in its chunk")
	t.check(total_nodes > 3000, "the world has plenty to gather (%d)" % total_nodes)
	t.check(loose_pickups > 100, "seeded world includes pickable modeled stones (%d)" % loose_pickups)
	t.check(modeled_boulders > 20, "seeded world includes mineable modeled rocks (%d)" % modeled_boulders)
	t.check(roadside_caches > 0, "roads contain collectible traveler caches (%d)" % roadside_caches)
	t.check(roadside_ambushes > 0, "dangerous roadside caches can be guarded (%d)" % roadside_ambushes)
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

	t.current = "depleted stone collision matches visible model"
	var blocked_stone: Dictionary = {}
	for candidate in a.chunk(Vector2i(8, 8))["nodes"]:
		if str(candidate["kind"]) == "rock" and candidate.has("stone_model"):
			blocked_stone = candidate
			break
	if blocked_stone.is_empty():
		for cx in range(6, 10):
			if not blocked_stone.is_empty():
				break
			for cz in range(6, 10):
				if not blocked_stone.is_empty():
					break
				for candidate in a.chunk(Vector2i(cx, cz))["nodes"]:
					if str(candidate["kind"]) == "rock" and candidate.has("stone_model"):
						blocked_stone = candidate
						break
	t.check(not blocked_stone.is_empty(), "found an authoritative collidable model boulder")
	if not blocked_stone.is_empty():
		var bx: float = float(blocked_stone["x"])
		var bz: float = float(blocked_stone["z"])
		var b_id: int = int(blocked_stone["id"])
		var initially_blocked := false
		for obstacle in a.blockers_near(bx, bz, 0.5):
			if int(obstacle.get("id", -1)) == b_id:
				initially_blocked = true
		t.check(initially_blocked, "visible modeled boulder blocks movement")
		a.set_node_depleted(b_id, true)
		var mined_blocked := false
		for obstacle in a.blockers_near(bx, bz, 0.5):
			if int(obstacle.get("id", -1)) == b_id:
				mined_blocked = true
		t.check(not mined_blocked, "mined modeled boulder has no invisible collision")
		a.set_node_depleted(b_id, false)
		var regrown_blocked := false
		for obstacle in a.blockers_near(bx, bz, 0.5):
			if int(obstacle.get("id", -1)) == b_id:
				regrown_blocked = true
		t.check(regrown_blocked, "respawn restores modeled boulder collision")
		var snapshot_depleted: Dictionary = {}
		snapshot_depleted[b_id] = true
		a.sync_depleted_nodes(snapshot_depleted)
		t.check(a.depleted_blockers.has(b_id), "snapshot-depleted node disables local prediction blocker")
		a.sync_depleted_nodes({})
		t.check(not a.depleted_blockers.has(b_id), "snapshot correction restores local blocker")

	t.current = "structures"
	var hub: Array = a.hub_structures()
	t.check(hub.size() >= 10, "the hub has a fountain, a workbench and houses (%d)" % hub.size())
	var kinds: Dictionary = {}
	for s in hub:
		kinds[s["kind"]] = true
		t.check(s["radius"] > 0.0 and s["scale"] > 0.0, "hub structure sizes are positive")
	t.check(kinds.has("fountain") and kinds.has("workbench") and kinds.has("building"), "all hub structure kinds exist")
	t.eq(hub, b.hub_structures(), "the hub is the same for the same seed")
	for s in hub:
		if s["kind"] == "building":
			t.check(Vector2(s["x"], s["z"]).length() > 28.0, "houses stand outside the spawn ring")
			var near_house := a.blockers_near(s["x"], s["z"], 0.3)
			var found := false
			for blocker in near_house:
				if blocker["kind"] == "building" and blocker["x"] == s["x"] and blocker["z"] == s["z"]:
					found = true
			t.check(found, "a house blocks movement at its own position")
	t.check(a.blockers_near(0.0, 0.0, 1.5).is_empty(), "the fountain basin and the spawn area are open")
	var ruin_structures := 0
	var ruin_walls := 0
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var chunk_data := a.chunk(Vector2i(cx, cz))
			if not chunk_data["ruin"] and a.poi.sites_near(float(cx) * 64.0 + 32.0, float(cz) * 64.0 + 32.0, 48.0).is_empty():
				t.eq(chunk_data["structures"].size(), 0, "only ruins and sites have structures")
			for s in chunk_data["structures"]:
				ruin_structures += 1
				ruin_walls += 1 if s["kind"] == "wall" else 0
				t.eq(WorldGen.cell_of(s["x"], s["z"]), Vector2i(cx, cz), "a structure lies in its chunk")
				t.check(not a.is_water(s["x"], s["z"]), "structures are not in water")
	t.check(ruin_structures > 20 and ruin_walls > 3, "ruins hold buildings and walls (%d, %d walls)" % [ruin_structures, ruin_walls])

	t.current = "bounded LRU cache prevents mass chunk regeneration"
	var first_stats: Dictionary = a.chunk_cache_stats()
	t.check(int(first_stats["size"]) <= WorldGen.CACHE_LIMIT,
		"world never keeps more than its chunk cache capacity")
	t.eq(int(first_stats["collision_chunks"]), int(first_stats["size"]),
		"collision broadphase has one matching entry for each cached chunk")
	var cold_cell := Vector2i(-220, -220)
	var hot_cell := Vector2i(-221, -220)
	var cold: Dictionary = a.chunk(cold_cell)
	var hot: Dictionary = a.chunk(hot_cell)
	cold["_cache_test_marker"] = "should_evicted"
	hot["_cache_test_marker"] = "recently_used"
	var evictions_before: int = int(a.chunk_cache_stats()["evictions"])
	for index in range(WorldGen.CACHE_LIMIT + 8):
		a.chunk(Vector2i(-300 - index, -350))
		if index % 4 == 0:
			a.chunk(hot_cell)
	var cache_report: Dictionary = a.chunk_cache_stats()
	t.eq(a.chunk_cache_size(), WorldGen.CACHE_LIMIT,
		"cache retains at most 256 recent cells even after a long journey")
	t.eq(int(cache_report["collision_chunks"]), a.chunk_cache_size(),
		"solid-only collision entries evict with their source chunks")
	t.check(int(cache_report["evictions"]) > evictions_before,
		"pressure evicts individual old chunks rather than clearing all")
	t.eq(str(a.chunk(hot_cell).get("_cache_test_marker", "")), "recently_used",
		"frequently visited chunks stay hot throughout cache pressure")
	t.check(not a.chunk(cold_cell).has("_cache_test_marker"),
		"long-unvisited chunks regenerate deterministically when revisited")
	var miss_before: int = int(a.chunk_cache_stats()["misses"])
	var hit_before: int = int(a.chunk_cache_stats()["hits"])
	var visited_again: Dictionary = a.chunk(hot_cell)
	t.eq(visited_again.get("_cache_test_marker"), "recently_used",
		"cache hits return the existing generated chunk object")
	t.eq(int(a.chunk_cache_stats()["misses"]), miss_before,
		"cache hit avoids extra world generation")
	t.check(int(a.chunk_cache_stats()["hits"]) > hit_before,
		"cache diagnostics count reuse without iterating chunk contents")
	t.check(a.chunk_cache_hit_percent() > 0.0 and a.chunk_cache_hit_percent() <= 100.0,
		"profiler hit percentage stays within meaningful bounds")

	t.current = "collision broadphase stays live across eviction and build changes"
	var dynamic_id: int = 735199
	var wall_x: float = -15000.0
	var wall_z: float = -15000.0
	a.add_dynamic_blocker(dynamic_id, wall_x, wall_z, 1.1)
	var dynamic_found: bool = false
	for obstacle in a.blockers_near(wall_x, wall_z, 0.5):
		if int(obstacle.get("id", -1)) == dynamic_id:
			dynamic_found = true
	t.check(dynamic_found, "new build is collidable after static cache churn")
	a.remove_dynamic_blocker(dynamic_id)
	var dynamic_removed: bool = true
	for obstacle in a.blockers_near(wall_x, wall_z, 0.5):
		if int(obstacle.get("id", -1)) == dynamic_id:
			dynamic_removed = false
	t.check(dynamic_removed, "removing a build immediately removes its collision")
	if not blocked_stone.is_empty():
		var stone_center: Vector2 = Vector2(float(blocked_stone["x"]), float(blocked_stone["z"]))
		var stone_found: bool = false
		for obstacle in a.blockers_near(stone_center.x, stone_center.y, 0.5):
			if int(obstacle.get("id", -1)) == int(blocked_stone["id"]):
				stone_found = true
		t.check(stone_found, "procedural rock collision returns after LRU regeneration")
		var actual_ids: Array[int] = []
		for obstacle in a.blockers_near(stone_center.x, stone_center.y, 0.5):
			actual_ids.append(int(obstacle["id"]))
		t.eq(actual_ids, _reference_procedural_blockers(a, stone_center.x, stone_center.y, 0.5),
			"solid-only index preserves exhaustive collision results and iteration order")
		a.set_node_depleted(int(blocked_stone["id"]), true)
		actual_ids.clear()
		for obstacle in a.blockers_near(stone_center.x, stone_center.y, 0.5):
			actual_ids.append(int(obstacle["id"]))
		t.eq(actual_ids, _reference_procedural_blockers(a, stone_center.x, stone_center.y, 0.5),
			"solid index matches full scans after resource depletion")
		a.set_node_depleted(int(blocked_stone["id"]), false)

	t.current = "incremental built-obstacle grid matches exact legacy collider scan"
	var built_grid := DynamicBlockerGrid.new()
	var live: Dictionary = {}
	live[11] = {"id": 11, "x": 15.0, "z": -1.0, "radius": 2.0}
	built_grid.upsert(11, live[11])
	live["12:0"] = {"id": 12, "x": 32.5, "z": -1.0, "radius": 1.5}
	built_grid.upsert("12:0", live["12:0"])
	live[13] = {"id": 13, "x": 100.0, "z": 100.0, "radius": 1.0}
	built_grid.upsert(13, live[13])
	t.eq(built_grid.query(live, 17.0, -1.0, 0.0).size(), 1,
		"large wall remains searchable across a 16m cell boundary")
	t.eq(built_grid.query(live, 17.0, -1.0, 0.0)[0]["id"], 11,
		"touching the collision edge remains blocked, not just overlapping it")
	t.eq(built_grid.query(live, -100.0, -100.0, 0.0).size(), 0,
		"distant built obstacles are excluded")
	t.eq(built_grid.last_candidates, 0, "empty local cells avoid scanning all built structures")
	t.eq(built_grid.query(live, 30.0, -1.0, 3.0).size(), 1,
		"multipart house walls participate in the same grid")
	t.eq(built_grid.query(live, 32.0, -1.0, 20.0).size(), 2,
		"one overlapping wall appears once despite occupying several cells")
	var original_order: Array[int] = []
	for wall in live.values():
		if absf(float(wall["x"]) - 32.0) <= 20.0 + float(wall["radius"]) \
				and absf(float(wall["z"]) + 1.0) <= 20.0 + float(wall["radius"]):
			original_order.append(int(wall["id"]))
	var indexed_order: Array[int] = []
	for wall in built_grid.query(live, 32.0, -1.0, 20.0):
		indexed_order.append(int(wall["id"]))
	t.eq(indexed_order, original_order,
		"mixed integer and string keys keep the original collision resolution order")
	live[11] = {"id": 11, "x": -32.0, "z": -32.0, "radius": 3.0}
	built_grid.upsert(11, live[11])
	t.eq(built_grid.query(live, 15.0, -1.0, 0.0).size(), 0,
		"moving a built blocker removes old indexed footprint immediately")
	t.eq(built_grid.query(live, -35.0, -32.0, 0.0)[0]["id"], 11,
		"moving a wall updates negative-coordinate cells")
	built_grid.remove("12:0")
	live.erase("12:0")
	t.eq(built_grid.query(live, 32.5, -1.0, 0.0).size(), 0,
		"removing house parts invalidates all old cells")
	var huge: Dictionary = {"id": 99, "x": 0.0, "z": 0.0, "radius": 180.0}
	live[99] = huge
	built_grid.upsert(99, huge)
	t.eq(int(built_grid.stats()["oversized"]), 1,
		"oversized walls stay in a bounded fallback instead of multiplying memory")
	t.eq(built_grid.query(live, 170.0, 0.0, 0.0)[0]["id"], 99,
		"overflow obstacles still block at the correct distance")
	t.eq(built_grid.query(live, -300.0, -300.0, 600.0).size(), live.size(),
		"very broad queries fall back to an exhaustive scan")
	t.eq(built_grid.last_candidates, live.size(),
		"large-radius fallback reports the real number of tested obstacles")
	var index_size: int = int(built_grid.stats()["entries"])
	built_grid.upsert(42, {"id": 42, "x": NAN, "z": 1.0, "radius": 1.0})
	t.eq(int(built_grid.stats()["entries"]), index_size, "invalid geometry is not indexed")

	t.current = "indexed dynamic collisions agree with exhaustive deterministic queries"
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 812719
	var many: Dictionary = {}
	var spatial := DynamicBlockerGrid.new()
	for i in 120:
		var key: int = 2000 + i
		var bx: float = seeded.randf_range(-300.0, 300.0)
		var bz: float = seeded.randf_range(-300.0, 300.0)
		var br: float = seeded.randf_range(0.2, 11.0)
		var blocker: Dictionary = {"id": key, "x": bx, "z": bz, "radius": br}
		many[key] = blocker
		spatial.upsert(key, blocker)
	for sample in 48:
		var qx: float = seeded.randf_range(-310.0, 310.0)
		var qz: float = seeded.randf_range(-310.0, 310.0)
		var reach: float = seeded.randf_range(0.0, 30.0)
		var expected: Array[int] = []
		for item in many.values():
			var r: float = reach + float(item["radius"])
			if absf(float(item["x"]) - qx) <= r and absf(float(item["z"]) - qz) <= r:
				expected.append(int(item["id"]))
		var actual: Array[int] = []
		for item in spatial.query(many, qx, qz, reach):
			actual.append(int(item["id"]))
		t.eq(actual, expected, "spatial query %d matches exhaustive ordered lookup" % sample)
	for i in range(10):
		var stale_key: int = 2000 + i
		spatial.remove(stale_key)
		many.erase(stale_key)
	for sample in 24:
		var qx: float = seeded.randf_range(-310.0, 310.0)
		var qz: float = seeded.randf_range(-310.0, 310.0)
		var expected: Array[int] = []
		for item in many.values():
			if absf(float(item["x"]) - qx) <= 18.0 + float(item["radius"]) \
					and absf(float(item["z"]) - qz) <= 18.0 + float(item["radius"]):
				expected.append(int(item["id"]))
		var actual: Array[int] = []
		for item in spatial.query(many, qx, qz, 18.0):
			actual.append(int(item["id"]))
		t.eq(actual, expected, "index remains accurate after removals %d" % sample)

	t.current = "world build events update spatial collision index immediately"
	var construction := WorldGen.new(139)
	var building_id: int = 900077
	construction.add_structure_blockers(building_id, [[-100.0, -100.0, 1.0],
		[-92.0, -100.0, 0.6]])
	t.eq(construction.dynamic_blocker_count(), 2, "two house wall circles are indexed")
	t.eq(int(construction.dynamic_blocker_stats()["entries"]), 2,
		"world and spatial index remain in sync")
	var parts_near: Array = []
	for wall in construction.blockers_near(-100.0, -100.0, 0.1):
		if int(wall.get("id", -1)) == building_id:
			parts_near.append(wall)
	t.eq(parts_near.size(), 1, "house wall immediately blocks movement")
	construction.add_structure_blockers(building_id, [[-80.0, -100.0, 1.0]])
	t.eq(construction.dynamic_blocker_count(), 1, "changing a door removes old wall parts")
	var stale: bool = false
	for wall in construction.blockers_near(-100.0, -100.0, 0.1):
		if int(wall.get("id", -1)) == building_id:
			stale = true
	t.check(not stale, "open doorway has no invisible old wall collision")
	construction.add_dynamic_blocker(building_id, -60.0, -100.0, 1.0)
	t.eq(construction.dynamic_blocker_count(), 1,
		"converting a house to a single obstacle removes prior parts")
	var replacement: bool = false
	for wall in construction.blockers_near(-60.0, -100.0, 0.1):
		if int(wall.get("id", -1)) == building_id:
			replacement = true
	t.check(replacement, "single structure collision is visible in new position")
	construction.remove_dynamic_blocker(building_id)
	t.eq(construction.dynamic_blocker_count(), 0, "demolition removes all indexed blockers")
	t.eq(int(construction.dynamic_blocker_stats()["tiles"]), 0,
		"all empty spatial buckets are released after demolition")
