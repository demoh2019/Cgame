extends RefCounted
## Authoritative network-interest filtering, input-order safety and
## snapshot broadcast lifecycle. Stock Godot runs the unindexed path.

const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


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
	t.eq(indexed["players"], baseline["players"],
		"native index never changes replicated player payload or ordering")
	t.eq(indexed["zombies"], baseline["zombies"],
		"native index never changes replicated infected payload or ordering")
	server.finish_snapshot_interest()
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

	t.current = "real Net sends one shared index per snapshot cadence"
	var net_source: String = (Net as Script).source_code
	t.check(net_source.contains('sim.prepare_snapshot_interest()'),
		"one network broadcast prepares index before per-peer snapshots")
	t.check(net_source.contains('sim.finish_snapshot_interest()'),
		"network broadcast retires index after all viewers")
