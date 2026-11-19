extends RefCounted
## Checkpoint regression for the canonical dedicated GameServer, no socket required.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")
const BarricadeTests = preload("res://tests/test_barricades.gd")
const TEST_PATH := "user://albion_after_world_persistence_test.json"


func _server(seed: int = 214):
	return GameServer.new(WorldGen.new(seed), 314)


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func _write_snapshot(data: Dictionary) -> bool:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


func run(t) -> void:
	t.current = "world checkpoint / initial owner"
	var server = _server()
	var spot: Vector2 = BarricadeTests.new()._find_place(server.world)
	t.check(spot != Vector2.ZERO, "found a collision-free site")
	if spot == Vector2.ZERO:
		return
	var builder = server.add_player(101, "Builder", "authenticated-user-a")
	var origin: Vector2 = spot + Vector2(-2.8, 0)
	builder.position = _at(server.world, origin)
	builder.inventory.add("wood_1", 15)
	builder.inventory.add("stone_1", 10)
	var built: Dictionary = server.cmd_build(101, spot.x, spot.y)
	t.check(bool(built.get("ok", false)), "account-owned wall built on server")
	if not bool(built.get("ok", false)):
		return
	var id: int = int(built["id"])
	t.eq(str(server.barricades[id].get("owner_account")), "authenticated-user-a", "stable owner ID stored privately")
	t.check(not server.snapshot_for(101)["barricades"][0].has("owner_account"), "backend ID not exposed to clients")
	server.damage_barricade(id, 35.0)
	var checkpoint: Dictionary = Persist.capture(server)
	t.eq(checkpoint["barricades"].size(), 1, "one authenticated wall included")
	t.eq(checkpoint["version"], Persist.VERSION, "world checkpoint schema version")
	t.check(Persist.save(server, TEST_PATH), "atomic checkpoint write succeeded")

	t.current = "new server / restored blockers and identity"
	var resumed = _server()
	t.check(Persist.load(resumed, TEST_PATH), "saved world loaded on fresh server")
	t.eq(resumed.barricades.size(), 1, "barricade restored")
	t.near(float(resumed.barricades[id]["hp"]), 85.0, 0.001, "damage survives restart")
	t.eq(int(resumed.barricades[id]["owner"]), -1, "old session peer is not trusted")
	t.check(not Movement._is_free(resumed.world, spot), "collision restored with world")
	t.check(resumed.new_id() > id, "new runtime IDs cannot collide with restored IDs")
	var impostor = resumed.add_player(101, "Impostor")
	impostor.position = _at(resumed.world, origin)
	impostor.inventory.add("wood_1", 10)
	t.eq(resumed.cmd_repair(101, id).get("reason"), "not_owner", "recycled guest peer cannot claim wall")
	var stranger = resumed.add_player(102, "Stranger", "authenticated-user-b")
	stranger.position = _at(resumed.world, origin)
	stranger.inventory.add("wood_1", 10)
	t.eq(resumed.cmd_repair(102, id).get("reason"), "not_owner", "different account cannot repair")
	var owner = resumed.add_player(103, "Owner", "authenticated-user-a")
	owner.position = _at(resumed.world, origin)
	owner.inventory.add("wood_1", 10)
	t.eq(int(resumed.barricades[id]["owner"]), 103, "reconnected account rebinds public owner peer")
	t.check(bool(resumed.cmd_repair(103, id).get("ok", false)), "authenticated owner repairs after restart")
	t.near(float(resumed.barricades[id]["hp"]), 120.0, 0.001, "durability restored")
	resumed.remove_player(103)
	t.eq(int(resumed.barricades[id]["owner"]), -1, "logout releases stale peer identity")
	var same_owner = resumed.add_player(104, "OwnerAgain", "authenticated-user-a")
	same_owner.position = _at(resumed.world, origin)
	t.eq(int(resumed.barricades[id]["owner"]), 104, "same account can reclaim on new peer ID")
	t.eq(resumed.cmd_repair(101, id).get("reason"), "not_owner", "original impostor remains unauthorized")
	t.check(not Persist.restore(resumed, checkpoint), "cannot reapply checkpoint to live world")

	t.current = "tamper-resistant snapshot schema"
	var foreign := checkpoint.duplicate(true)
	foreign["world_seed"] = 999
	var untouched = _server()
	t.check(not Persist.restore(untouched, foreign), "foreign world seed rejected")
	t.check(untouched.barricades.is_empty() and untouched.world.dynamic_blockers.is_empty(), "foreign seed did not partially mutate")
	var invalid_owner := checkpoint.duplicate(true)
	invalid_owner["barricades"][0]["owner_account"] = ""
	t.check(not Persist.restore(_server(), invalid_owner), "anonymous owner is not restored")
	var duplicate := checkpoint.duplicate(true)
	duplicate["barricades"].append(duplicate["barricades"][0].duplicate(true))
	t.check(not Persist.restore(_server(), duplicate), "duplicate structure IDs rejected")
	var bad_health := checkpoint.duplicate(true)
	bad_health["barricades"][0]["hp"] = -42
	t.check(not Persist.restore(_server(), bad_health), "negative wall health rejected")
	var bad_position := checkpoint.duplicate(true)
	bad_position["barricades"][0]["x"] = 0.0
	bad_position["barricades"][0]["z"] = 0.0
	t.check(not Persist.restore(_server(), bad_position), "safe-hub blocker rejected")
	var bad_id := checkpoint.duplicate(true)
	bad_id["barricades"][0]["id"] = 0
	t.check(not Persist.restore(_server(), bad_id), "invalid structure ID rejected")
	var invalid_schema := checkpoint.duplicate(true)
	invalid_schema["version"] = 2
	t.check(not Persist.restore(_server(), invalid_schema), "unknown version rejected")
	t.check(_write_snapshot(bad_health), "can write damaged fixture")
	var failed = _server()
	t.check(not Persist.load(failed, TEST_PATH), "bad checkpoint file rejected")
	t.check(failed.barricades.is_empty(), "failed load does not create walls")

	t.current = "guest walls cannot turn into durable ownership"
	var guests = _server()
	var guest = guests.add_player(55, "Guest")
	guest.position = _at(guests.world, origin)
	guest.inventory.add("wood_1", 4)
	guest.inventory.add("stone_1", 2)
	t.check(bool(guests.cmd_build(55, spot.x, spot.y).get("ok", false)), "offline guest can build for this session")
	t.eq(Persist.capture(guests)["barricades"].size(), 0, "offline guest wall does not persist as a claimable structure")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".tmp"))
