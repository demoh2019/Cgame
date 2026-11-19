extends RefCounted
## Persistent world regression: runs real server rules and actual FileAccess I/O,
## but never touches the production world snapshot path.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldState = preload("res://scripts/server/world_state.gd")
const WorldStore = preload("res://scripts/server/world_store.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const BarricadeTests = preload("res://tests/test_barricades.gd")
const SAVE_PATH := "user://tests/barricade_world_regression.json"
const SEED := 214


func _fresh_world():
	return GameServer.new(WorldGen.new(SEED), 314)


func _corrupt(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var bad: Dictionary = base.duplicate(true)
	bad["barricades"][0][key] = value
	return bad


func run(t) -> void:
	var old_path: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(old_path)
	var server = _fresh_world()
	var player = server.add_player(101, "Builder", "nakama-account-builder")
	var point: Vector2 = BarricadeTests.new()._find_place(server.world)
	t.current = "world save live entity, exact snapshot and disk roundtrip"
	t.check(point != Vector2.ZERO, "suitable open construction site exists")
	if point == Vector2.ZERO:
		return
	var initial := point + Vector2(-2.8, 0.0)
	player.position = Vector3(initial.x, server.world.height_at(initial.x, initial.y), initial.y)
	player.inventory.add("wood_1", 12)
	player.inventory.add("stone_1", 6)
	var built: Dictionary = server.cmd_build(101, point.x, point.y)
	t.check(built.get("ok", false), "a real account can construct a barricade")
	if not built.get("ok", false):
		return
	var id: int = int(built["id"])
	t.check(server.world_dirty, "new construction marks world dirty")
	t.eq(str(server.barricades[id]["owner_key"]), "account:nakama-account-builder", "persistent owner is authenticated account, not session peer")
	t.check(not server.damage_barricade(id, 33.0), "partial damage keeps structure alive")
	t.check(server.world_dirty, "damage marks world dirty")
	t.near(float(server.barricades[id]["hp"]), 87.0, 0.001, "damaged health recorded")
	var state: Dictionary = server.export_world_state()
	t.eq(state["version"], WorldState.VERSION, "saved document includes schema version")
	t.eq(state["seed"], SEED, "saved document is bound to exact world seed")
	t.eq(state["barricades"].size(), 1, "saved document includes a single barricade")
	t.check(not state["barricades"][0].has("y"), "Y reconstructed from deterministic terrain")
	t.check(not state["barricades"][0].has("owner"), "temporary peer IDs never persisted")
	t.check(not state["barricades"][0].has("user_id"), "backend user ID field not in public-compatible wall schema")
	var serialized: Variant = JSON.parse_string(JSON.stringify(state))
	t.check(WorldState.parse_state(WorldGen.new(SEED), serialized).get("ok", false), "JSON float-decoded IDs remain valid after strict integer check")
	t.check(WorldStore.save(server, SAVE_PATH), "write complete world state through atomic replacement")
	t.check(FileAccess.file_exists(SAVE_PATH), "snapshot exists on disk")

	var rebooted = _fresh_world()
	var loaded: Dictionary = WorldStore.load(rebooted, SAVE_PATH)
	t.check(bool(loaded.get("ok", false)), "fresh world restores from real disk")
	t.eq(loaded.get("count", 0), 1, "loaded structure count matches saved state")
	t.eq(rebooted.barricades.size(), 1, "authoritative world has restored wall")
	t.check(rebooted.world.dynamic_blockers.has(id), "restored world rebuilds movement collision")
	t.check(not Movement._is_free(rebooted.world, point), "restored wall still blocks player")
	t.near(float(rebooted.barricades[id]["hp"]), 87.0, 0.001, "damaged durability survives server restart")
	t.near(float(rebooted.barricades[id]["y"]), rebooted.world.height_at(point.x, point.y), 0.001, "restored height matches authoritative terrain")
	t.check(rebooted.new_id() > id, "new entity IDs do not collide with persisted structures")
	t.check(not rebooted.world_dirty, "restoring clean snapshot does not immediately rewrite disk")

	t.current = "owner can reconnect with new peer ID; impostor cannot"
	var thief = rebooted.add_player(500, "Builder", "different-account")
	thief.position = Vector3(initial.x, rebooted.world.height_at(initial.x, initial.y), initial.y)
	thief.inventory.add("wood_1", 4)
	t.eq(rebooted.cmd_repair(500, id).get("reason"), "not_owner", "same display name cannot hijack another account's base")
	var owner = rebooted.add_player(700, "NewNick", "nakama-account-builder")
	owner.position = Vector3(initial.x, rebooted.world.height_at(initial.x, initial.y), initial.y)
	owner.inventory.add("wood_1", 3)
	var repaired: Dictionary = rebooted.cmd_repair(700, id)
	t.check(repaired.get("ok", false), "same authenticated account repairs using different network peer")
	t.near(float(rebooted.barricades[id]["hp"]), 120.0, 0.001, "repaired health survives reconnect")
	t.eq(owner.inventory.count("wood_1"), 2, "owner spends one wood on repair")
	t.check(rebooted.world_dirty, "repair marks world dirty")
	t.check(WorldStore.save(rebooted, SAVE_PATH), "second snapshot atomically replaces first")
	var after_repair = _fresh_world()
	t.check(WorldStore.load(after_repair, SAVE_PATH).get("ok", false), "replaced snapshot reloads")
	t.near(float(after_repair.barricades[id]["hp"]), 120.0, 0.001, "replacement file contains repaired health")
	t.check(after_repair.damage_barricade(id, 1000.0), "destroying saved wall removes it")
	t.check(after_repair.world_dirty, "destruction marks world dirty")
	t.check(WorldStore.save(after_repair, SAVE_PATH), "destruction writes empty authoritative structures list")
	var after_destroy = _fresh_world()
	t.check(WorldStore.load(after_destroy, SAVE_PATH).get("ok", false), "destroyed wall state reloads")
	t.eq(after_destroy.barricades.size(), 0, "destroyed wall cannot resurrect on next restart")
	t.check(Movement._is_free(after_destroy.world, point), "destroyed wall no longer blocks saved world")

	t.current = "tampering must never partly restore or overwrite existing world"
	var bad: Dictionary = _corrupt(state, "hp", -100.0)
	var invalid = _fresh_world()
	t.eq(invalid.restore_world_state(bad).get("reason"), "bad_health", "reject negative durability")
	t.eq(invalid.barricades.size(), 0, "rejected snapshot leaves world empty")
	t.eq(invalid.world.dynamic_blockers.size(), 0, "rejected snapshot creates no partial collisions")
	bad = _corrupt(state, "owner_key", "a-forged-peer")
	t.eq(invalid.restore_world_state(bad).get("reason"), "bad_owner", "reject invalid ownership")
	bad = _corrupt(state, "id", 5000000001.5)
	t.eq(invalid.restore_world_state(bad).get("reason"), "bad_id", "reject fractional entity IDs")
	bad = _corrupt(state, "x", NAN)
	t.eq(invalid.restore_world_state(bad).get("reason"), "bad_number", "reject nonfinite coordinates")
	bad = state.duplicate(true)
	bad["seed"] = SEED + 1
	t.eq(invalid.restore_world_state(bad).get("reason"), "wrong_seed", "refuse world data for a different terrain seed")
	bad = state.duplicate(true)
	bad["version"] = WorldState.VERSION + 1
	t.eq(invalid.restore_world_state(bad).get("reason"), "wrong_version", "reject unknown save format")
	bad = state.duplicate(true)
	bad["barricades"].append(state["barricades"][0].duplicate(true))
	t.eq(invalid.restore_world_state(bad).get("reason"), "duplicate_id", "refuse duplicate barricade IDs")
	bad = state.duplicate(true)
	var overlap: Dictionary = state["barricades"][0].duplicate(true)
	overlap["id"] = id + 1
	bad["barricades"].append(overlap)
	t.eq(invalid.restore_world_state(bad).get("reason"), "wall_overlap", "reject overlapping structures even with different IDs")
	t.eq(invalid.barricades.size(), 0, "multiple malformed restores never mutate the live simulation")
	t.check(not invalid.restore_world_state({}).get("ok", false), "empty dict is not silently treated as a new world")
	t.check(invalid.restore_world_state(state).get("ok", false), "a valid snapshot still loads after failures")
	t.eq(invalid.restore_world_state(state).get("reason"), "world_not_empty", "cannot overwrite live world with a second snapshot")

	t.current = "corrupt file fails closed and is left available for recovery"
	var handle: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	t.check(handle != null, "test file is writable")
	if handle != null:
		handle.store_string("{ broken json")
		handle.close()
		var corrupt_target = _fresh_world()
		t.eq(WorldStore.load(corrupt_target, SAVE_PATH).get("reason"), "invalid_json", "corrupt save is rejected, not ignored")
		t.eq(corrupt_target.barricades.size(), 0, "corrupt file cannot mutate new world")
		t.check(FileAccess.file_exists(SAVE_PATH), "corrupt save retained for manual recovery")
	DirAccess.remove_absolute(old_path)
