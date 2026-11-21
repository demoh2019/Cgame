extends RefCounted
## Exercises the exact server-side spatial broadphase, including a live
## GameServer infected population maintenance pass. No client commands.

const PresenceGrid = preload("res://scripts/server/player_presence_grid.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


class EmptyChunkWorld:
	extends RefCounted
	func chunk(_coord: Vector2i) -> Dictionary:
		return {"spawns": []}


func _brute(points: Array[Vector2], query: Vector2, radius: float,
		inclusive: bool) -> bool:
	for point in points:
		var d: float = query.distance_squared_to(point)
		if (inclusive and d <= radius * radius) or (not inclusive and d < radius * radius):
			return true
	return false


func run(t) -> void:
	t.current = "player spatial broadphase: grid boundaries, empty/invalid and strict radii"
	t.eq(PresenceGrid.cell_of(Vector2.ZERO), Vector2i.ZERO, "origin belongs to zero cell")
	t.eq(PresenceGrid.cell_of(Vector2(-0.1, -64.1)), Vector2i(-1, -2),
		"negative coordinates floor toward minus infinity")
	var grid := PresenceGrid.new()
	t.check(not grid.any_within(Vector2.ZERO, 12.0), "empty grid cannot report survivor")
	var single: Array[Vector2] = [Vector2(-64.0, -1.0)]
	grid.rebuild(single)
	t.check(grid.any_within(Vector2(-64.0, -1.0), 0.0),
		"zero-radius inclusive query accepts same position")
	t.check(not grid.any_within(Vector2(-64.0, -1.0), 0.0, false),
		"zero-radius strict query rejects exact equality")
	t.check(grid.any_within(Vector2(-52.0, -1.0), 12.0),
		"inclusive retention accepts exact boundary")
	t.check(not grid.any_within(Vector2(-52.0, -1.0), 12.0, false),
		"strict anti-spawn test rejects exact 12m")
	t.check(grid.any_within(Vector2(-52.01, -1.0), 12.0, false),
		"strict radius accepts inside boundary")
	t.check(not grid.any_within(Vector2(NAN, 0), 12.0), "invalid query fails closed")
	t.check(not grid.any_within(Vector2.ZERO, NAN), "invalid radius fails closed")
	t.check(not grid.any_within(Vector2.ZERO, -1.0), "negative radius fails closed")
	t.eq(grid.snapshot()["alive_players"], 1, "single player index size")
	t.check(not grid.snapshot()["indexed_mode"], "solo mode scans without hash overhead")
	t.eq(grid.snapshot()["occupied_cells"], 0, "small mode allocates no spatial buckets")

	t.current = "spatial broadphase matches brute-force distance under negative coordinates"
	var many: Array[Vector2] = []
	var random := RandomNumberGenerator.new()
	random.seed = 10515
	for i in 40:
		many.append(Vector2(random.randf_range(-1600.0, 1600.0),
			random.randf_range(-1600.0, 1600.0)))
	many.append(Vector2.INF)
	grid.rebuild(many)
	t.eq(grid.snapshot()["alive_players"], 40, "nonfinite player positions are rejected")
	t.check(grid.snapshot()["indexed_mode"], "larger player count uses spatial buckets")
	t.check(grid.snapshot()["occupied_cells"] > 1, "world distributed across cells")
	var valid_points: Array[Vector2] = many.slice(0, 40)
	for i in 90:
		var location := Vector2(random.randf_range(-1800.0, 1800.0),
			random.randf_range(-1800.0, 1800.0))
		for radius in [0.0, 12.0, 64.0, 130.0, 256.0]:
			for inclusive in [true, false]:
				t.eq(grid.any_within(location, radius, inclusive),
					_brute(valid_points, location, radius, inclusive),
					"broadphase matches exact original rule for query %d" % i)
	var snapshot: Dictionary = grid.snapshot()
	t.check(snapshot["queries"] >= 900, "broadphase query accounting")
	t.check(snapshot["bucket_lookups"] > 0, "large groups use cell lookup")
	var lookups_before: int = grid.bucket_lookups
	t.check(grid.any_within(Vector2.ZERO, 1000000.0),
		"large-radius fallback still finds a real player")
	t.eq(grid.bucket_lookups, lookups_before,
		"oversized radius does not iterate millions of empty buckets")
	t.check(snapshot["candidate_checks"] < snapshot["queries"] * many.size(),
		"spatial candidates are pruned relative to full scans")

	t.current = "GameServer uses freshly rebuilt presence for zombie retention"
	var server := GameServer.new(WorldGen.new(11121), 11121)
	var survivor = server.add_player(314, "GridTester")
	server.world = EmptyChunkWorld.new() # No procedural spawns; isolation fixture.
	survivor.position = Vector3(-20.0, 0.0, -30.0)
	var near := Zombie.new(9001, "walker", Vector3(-20.0, 0.0, -35.0))
	var distant := Zombie.new(9002, "walker", Vector3(700.0, 0.0, 700.0))
	server.zombies[near.id] = near
	server.zombies[distant.id] = distant
	server._manage_zombie_population()
	t.check(server.zombies.has(near.id), "nearby living infected remains loaded")
	t.check(not server.zombies.has(distant.id), "distant infected is unloaded")
	t.eq(server.last_population_query_stats["alive_players"], 1,
		"server population maintenance built exact active player snapshot")
	t.check(server.last_population_query_stats["queries"] >= 2,
		"server uses index in real unload decisions")
	survivor.position = Vector3(700.0, 0.0, 700.0)
	server._manage_zombie_population()
	t.check(not server.zombies.has(near.id), "next pass reflects player relocation")
	t.eq(server.last_population_query_stats["alive_players"], 1,
		"player position is not cached between population maintenance passes")

	# Native Cgame does all broadphase math in C++ while stock Godot keeps
	# the authoritative script implementation. Both must agree bit for bit.
	if ClassDB.class_exists("SpatialPointGrid2D"):
		t.current = "native SpatialPointGrid2D: server semantics and GDScript parity"
		var native = ClassDB.instantiate("SpatialPointGrid2D")
		t.check(native != null, "native broadphase class instantiates")
		native.rebuild(single)
		t.eq(native.snapshot()["alive_players"], 1, "native solo count")
		t.check(not native.snapshot()["indexed_mode"], "native solo scans directly")
		t.check(native.any_within(Vector2(-52.0, -1.0), 12.0), "native inclusive boundary")
		t.check(not native.any_within(Vector2(-52.0, -1.0), 12.0, false),
			"native strict anti-spawn boundary")
		t.check(not native.any_within(Vector2(NAN, 0.0), 12.0), "native nonfinite query rejected")
		native.rebuild(many)
		t.eq(native.snapshot()["alive_players"], 40, "native rejects nonfinite positions")
		t.check(native.snapshot()["indexed_mode"], "native large server uses buckets")
		var random_parity := RandomNumberGenerator.new()
		random_parity.seed = 448411
		for index in range(90):
			var point := Vector2(random_parity.randf_range(-1800.0, 1800.0),
				random_parity.randf_range(-1800.0, 1800.0))
			for radius in [0.0, 12.0, 64.0, 130.0, 256.0]:
				for inclusive in [true, false]:
					t.eq(native.any_within(point, radius, inclusive),
						_brute(valid_points, point, radius, inclusive),
						"native broadphase agrees with brute force at case %d" % index)
		t.check(native.snapshot()["bucket_lookups"] > 0, "native indexed lookups counted")
		var old_buckets: int = native.snapshot()["bucket_lookups"]
		t.check(native.any_within(Vector2.ZERO, 1000000.0), "native large radius exact fallback")
		t.eq(native.snapshot()["bucket_lookups"], old_buckets,
			"native oversized query does not expand a huge bucket square")
		t.check(server.last_population_query_stats.get("native_backend", false),
			"the real GameServer uses the C++ broadphase under Cgame")
		native.clear()
		t.eq(native.snapshot()["queries"], 0, "native clear resets diagnostics")
