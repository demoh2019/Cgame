extends RefCounted
## Authoritative network-interest filtering, input-order safety and
## snapshot broadcast lifecycle. Stock Godot runs the unindexed path.

const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")
const BarricadeSnapshotIndex = preload("res://scripts/shared/barricade_snapshot_index.gd")
const Structures = preload("res://scripts/shared/structures.gd")


func run(t) -> void:
	t.current = "spatial network relevancy: engine API and exact radius"
	var player_positions := PackedVector2Array([
		Vector2(-20, -20), Vector2(1000, 1000), Vector2(70, -20),
		Vector2(200, 0), Vector2(-20, -110), Vector2(-20, -111),
		Vector2(-250, 0), Vector2(0, 0), Vector2(300, 300)])
	var player_ids := PackedInt64Array([3, 55, 7, 100, 9, 88, 12, 90, 24])
	var native = null
	if ClassDB.class_exists("SpatialRelevancyGrid2D"):
		native = ClassDB.instantiate("SpatialRelevancyGrid2D")
		t.check(native != null, "native network interest class is registered")
		t.check(native.rebuild(player_ids, player_positions), "native index builds")
		t.eq(native.query_ids(Vector2(-20, -20), 90.0),
			PackedInt64Array([3, 7, 9, 90]), "ordered exact 90m relevance")
		t.eq(native.query_ids(Vector2(700, 700), 90.0).size(), 0,
			"empty distant query cannot reveal unrelated entities")
		t.check(native.get_stats()["indexed_mode"], "large peer sets use buckets")
		t.eq(native.query_ids(Vector2(-20, -20), 0.0),
			PackedInt64Array([3]), "zero-radius picks the exact position")
		t.eq(native.query_ids(Vector2(-20, -20), 100000.0), player_ids,
			"large-radius fallback still preserves source order")
		t.check(not native.rebuild(PackedInt64Array([1, 1]),
			PackedVector2Array([Vector2.ZERO, Vector2.ONE])),
			"duplicate entity ids fail closed and use caller fallback")
		t.check(not native.rebuild(PackedInt64Array([1]),
			PackedVector2Array([Vector2(NAN, 0)])),
			"invalid entities cannot silently disappear")
		t.eq(native.get_stats()["entities"], 0,
			"failed rebuild clears partially indexed state")
		t.check(native.rebuild(player_ids, player_positions), "batch test restores native index")
		var multi_viewers := PackedVector2Array([
			Vector2(-20, -20), Vector2(0, 0), Vector2(700, 700), Vector2(NAN, 0)])
		var grouped: Array = native.query_many(multi_viewers, 90.0)
		t.eq(grouped.size(), multi_viewers.size(), "native produces one set per viewer")
		for i in multi_viewers.size():
			t.eq(grouped[i], native.query_ids(multi_viewers[i], 90.0),
				"native batch preserves exact scalar set at viewer %d" % i)
		t.eq(native.get_stats()["batch_calls"], 1, "one batch invocation recorded")
		t.eq(native.get_stats()["batch_viewers"], multi_viewers.size(),
			"batch counts all viewers including invalid positions")
		var none: Array = native.query_many(PackedVector2Array(), 90.0)
		t.eq(none.size(), 0, "empty batch returns no viewer lists")
	else:
		t.check(not ClassDB.class_exists("SpatialRelevancyGrid2D"),
			"stock Godot intentionally preserves original snapshot loops")

	t.current = "actual GameServer snapshot lists and stale-state protection"
	var world := WorldGen.new(23110)
	var server := GameServer.new(world, 23110)
	var own = server.add_player(101, "RelevantViewer")
	var near_player = server.add_player(102, "NearFriend")
	var far_player = server.add_player(103, "HiddenFriend")
	own.position = Vector3(250, world.height_at(250, 250), 250)
	near_player.position = Vector3(260, world.height_at(260, 250), 250)
	far_player.position = Vector3(700, world.height_at(700, 700), 700)
	var z_near := Zombie.new(50001, "walker", Vector3(253, 0, 251))
	var z_far := Zombie.new(50002, "walker", Vector3(900, 0, 900))
	server.zombies[z_near.id] = z_near
	server.zombies[z_far.id] = z_far
	var baseline: Dictionary = server.snapshot_for(101)
	t.eq(baseline["players"].size(), 1, "baseline sends only near player")
	t.eq(baseline["zombies"].size(), 1, "baseline sends only near infected")
	t.eq(int(baseline["players"][0]["id"]), 102, "baseline player id")
	t.eq(int(baseline["zombies"][0]["id"]), 50001, "baseline infected id")
	var started: bool = server.prepare_snapshot_interest()
	t.eq(started, native != null, "network interest index only active on Cgame")
	var indexed: Dictionary = server.snapshot_for(101)
	if started:
		t.eq(server._snapshot_player_ids_by_peer.size(), server.players.size(),
			"one cached player set per actual receiver")
		t.eq(server._snapshot_zombie_ids_by_peer.size(), server.players.size(),
			"one cached infected set per actual receiver")
		var p_stats: Dictionary = server._snapshot_players_grid.get_stats()
		var z_stats: Dictionary = server._snapshot_zombies_grid.get_stats()
		t.eq(p_stats["batch_calls"], 1, "native player index gathered in one call")
		t.eq(z_stats["batch_calls"], 1, "native infected index gathered in one call")
		t.eq(p_stats["queries"], server.players.size(),
			"one C++ query per viewer, not per snapshot invocation")
		t.eq(z_stats["queries"], server.players.size(),
			"all infected relevance precomputed before packet assembly")
	t.eq(indexed["players"], baseline["players"],
		"native index never changes replicated player payload or ordering")
	t.eq(indexed["zombies"], baseline["zombies"],
		"native index never changes replicated infected payload or ordering")
	server.finish_snapshot_interest()
	t.eq(server._snapshot_player_ids_by_peer.size(), 0,
		"broadcast completion clears cached player sets")
	t.eq(server._snapshot_zombie_ids_by_peer.size(), 0,
		"broadcast completion clears cached infected sets")
	t.eq(server.last_snapshot_interest_stats.get("enabled", false),
		native != null, "native diagnostics only when index was used")
	near_player.position = Vector3(700, 0, 700)
	z_near.position = Vector3(800, 0, 800)
	var fresh: Dictionary = server.snapshot_for(101)
	t.eq(fresh["players"].size(), 0, "outside broadcast, player positions are fresh")
	t.eq(fresh["zombies"].size(), 0, "outside broadcast, zombie positions are fresh")
	server.prepare_snapshot_interest()
	var after_move: Dictionary = server.snapshot_for(101)
	t.eq(after_move["players"], fresh["players"], "rebuild sees player teleport")
	t.eq(after_move["zombies"], fresh["zombies"], "rebuild sees infected relocation")
	server.finish_snapshot_interest()
	if started:
		t.eq(server.last_snapshot_interest_stats["players"]["batch_calls"], 1,
			"one player batch again after teleport rebuild")
		t.eq(server.last_snapshot_interest_stats["zombies"]["batch_calls"], 1,
			"one infected batch again after relocation rebuild")

	t.current = "real Net sends one shared index per snapshot cadence"
	var net_source: String = (Net as Script).source_code
	t.check(net_source.contains('sim.prepare_snapshot_interest()'),
		"one network broadcast prepares index before per-peer snapshots")
	t.check(net_source.contains('sim.finish_snapshot_interest()'),
		"network broadcast retires index after all viewers")

	t.current = "batched wall visibility matches full scans in crowded settlements"
	var packed_walls: Dictionary = {}
	var random := RandomNumberGenerator.new()
	random.seed = 9421008
	for i in 220:
		packed_walls[10000 + i] = {"id": 10000 + i,
			"x": random.randf_range(-350.0, 350.0),
			"z": random.randf_range(-350.0, 350.0),
			"hp": 120.0, "tier": 1, "upkeep_until": 7200.0,
			"owner": 201, "owner_account": "alpha"}
	var built: Dictionary = BarricadeSnapshotIndex.build(packed_walls, 30.0, {})
	t.eq((built["entries"] as Array).size(), packed_walls.size(),
		"one source slot per wall regardless of position")
	for sample in 90:
		var eye := Vector2(random.randf_range(-355.0, 355.0),
			random.randf_range(-355.0, 355.0))
		var radius: float = 90.0 if sample % 3 == 0 else (
			0.0 if sample % 3 == 1 else 140.0)
		var brute: Array[int] = []
		for wall in packed_walls.values():
			if Structures.within_range(eye, Vector2(float(wall["x"]),
					float(wall["z"])), radius):
				brute.append(int(wall["id"]))
		var actual: Array[int] = []
		for wall in BarricadeSnapshotIndex.visible(built, eye, radius):
			actual.append(int(wall["id"]))
		t.eq(actual, brute, "wall broadcast query %d preserves exact radius and source order" % sample)
	t.eq(BarricadeSnapshotIndex.visible(built, Vector2.ZERO, 100000.0).size(),
		packed_walls.size(), "huge interest uses bounded full-scan fallback")
	t.check(BarricadeSnapshotIndex.visible(built, Vector2(NAN, 0.0), 90.0).is_empty(),
		"invalid viewer coordinates cannot disclose nearby walls")
	t.check(BarricadeSnapshotIndex.visible(built, Vector2.ZERO, NAN).is_empty(),
		"invalid interest radius returns no structures")

	t.current = "private wall status and direction include only verified ownership"
	var own_wall: Dictionary = {"id": 30001, "x": 255.0, "y": 1.0, "z": 248.0,
		"hp": 40.0, "tier": 1, "owner": 201, "owner_account": "alpha",
		"upkeep_until": 60.0}
	var other_wall: Dictionary = {"id": 30002, "x": 800.0, "y": 1.0, "z": 800.0,
		"hp": 20.0, "tier": 1, "owner": 202, "owner_account": "beta",
		"upkeep_until": 60.0}
	var guest_wall: Dictionary = {"id": 30003, "x": -200.0, "y": 1.0, "z": -200.0,
		"hp": 120.0, "tier": 1, "owner": 201, "owner_account": "",
		"upkeep_until": 60.0}
	var owned_walls: Dictionary = {30001: own_wall, 30002: other_wall, 30003: guest_wall}
	var hits: Dictionary = {30001: 45.0, 30002: 49.0, 30003: 48.0}
	var summaries: Dictionary = BarricadeSnapshotIndex.build(owned_walls, 40.0, hits)
	var private_owner: Dictionary = BarricadeSnapshotIndex.private_status(summaries, 201, "alpha")
	t.eq(int(private_owner["at_risk"]), 2,
		"account and guest walls are both included only for their owner")
	t.eq(int(private_owner["damaged"]), 1, "critical wall damage counts only owned structures")
	t.eq(int(private_owner["under_attack"]), 2,
		"private warning counts both active attacks but not unrelated bases")
	t.near(float(private_owner["soonest_seconds"]), 20.0, 0.001,
		"nearest upkeep countdown is server-derived")
	t.near(float(private_owner["attack_x"]), -200.0, 0.001,
		"most recent owned attack chooses the correct distant wall, not another account")
	t.near(float(private_owner["attack_z"]), -200.0, 0.001,
		"private bearing includes the correct z coordinate")
	var outsider: Dictionary = BarricadeSnapshotIndex.private_status(summaries, 204, "gamma")
	t.eq(int(outsider["under_attack"]), 0, "third party cannot see any private attack")
	t.check(not outsider.has("attack_x") and not outsider.has("attack_z"),
		"unrelated players never receive private wall location hints")
	t.eq(int(BarricadeSnapshotIndex.private_status(summaries, 202, "beta")["under_attack"]), 1,
		"other account sees only its own active damage")
	t.eq(int(BarricadeSnapshotIndex.private_status(summaries, 201, "")["under_attack"]), 1,
		"unauthenticated guest only sees original peer-owned wall")
	t.check(not BarricadeSnapshotIndex.private_status(
			BarricadeSnapshotIndex.build(owned_walls, 100.0, hits),
			201, "alpha").has("attack_x"),
		"expired attacks never send stale coordinates or continue HUD alerts")

	t.current = "GameServer shares wall lists for the whole network broadcast"
	var wall_sim := GameServer.new(WorldGen.new(23110), 23111)
	var builder = wall_sim.add_player(201, "Builder", "alpha")
	var watcher = wall_sim.add_player(202, "Watcher", "beta")
	builder.position = Vector3(250, 1.0, 250)
	watcher.position = Vector3(800, 1.0, 800)
	wall_sim.time = 40.0
	wall_sim.barricades = owned_walls.duplicate(true)
	wall_sim._wall_infected_attack_until = hits.duplicate()
	var direct_owner: Dictionary = wall_sim.snapshot_for(201)
	var direct_watcher: Dictionary = wall_sim.snapshot_for(202)
	wall_sim.prepare_snapshot_interest()
	t.eq(wall_sim._snapshot_wall_tick, wall_sim.tick_count,
		"shared scripted wall cache is prepared even without optional native grid")
	t.eq((wall_sim._snapshot_wall_index["entries"] as Array).size(), 3,
		"one cache contains the whole authoritative wall population")
	var batched_owner: Dictionary = wall_sim.snapshot_for(201)
	var batched_watcher: Dictionary = wall_sim.snapshot_for(202)
	t.eq(batched_owner["barricades"], direct_owner["barricades"],
		"owner sees byte-equivalent visible wall records in indexed broadcast")
	t.eq(batched_watcher["barricades"], direct_watcher["barricades"],
		"other viewer sees unchanged private interest and public ordering")
	t.eq(batched_owner["you"]["base_upkeep"], direct_owner["you"]["base_upkeep"],
		"private owner alert and bearing match direct authoritative snapshot")
	t.eq(batched_watcher["you"]["base_upkeep"], direct_watcher["you"]["base_upkeep"],
		"other account receives identical private summary without leakage")
	wall_sim.finish_snapshot_interest()
	t.check(wall_sim._snapshot_wall_index.is_empty(), "finished broadcast releases cached wall entries")
	t.eq(int(wall_sim.last_snapshot_wall_stats["queries"]), 2,
		"two recipients reused the same one-pass wall index")
	t.eq(int(wall_sim.last_snapshot_wall_stats["walls"]), 3,
		"wall interest diagnostics report actual server structures")

	t.current = "wall mutation during a pending broadcast invalidates cached data"
	wall_sim.prepare_snapshot_interest()
	var old_hp: float = float(wall_sim.barricades[30001]["hp"])
	t.check(not wall_sim.damage_barricade(30001, 5.0), "live damage updates wall without destruction")
	t.check(float(wall_sim.barricades[30001]["hp"]) < old_hp,
		"damage uses authoritative structure durability")
	var corrected: Dictionary = wall_sim.snapshot_for(201)
	t.eq(corrected["barricades"][0]["hp"], wall_sim.barricades[30001]["hp"],
		"stale broadcast cache never hides wall durability changes")
	t.eq(int(corrected["you"]["base_upkeep"]["under_attack"]), 2,
		"stale cache fallback rebuilds the owner's private attack status")
	wall_sim.finish_snapshot_interest()
