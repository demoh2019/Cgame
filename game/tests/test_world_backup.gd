extends RefCounted
## Real-file backup rotation tests. Never writes to the production world save.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")
const BarricadeTests = preload("res://tests/test_barricades.gd")
const SAVE_PATH := "user://tests/world_backup_rotation.json"


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var value: String = file.get_as_text()
	file.close()
	return value


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var absolute: String = ProjectSettings.globalize_path(SAVE_PATH + suffix)
		if FileAccess.file_exists(SAVE_PATH + suffix):
			DirAccess.remove_absolute(absolute)


func _new_server():
	return GameServer.new(WorldGen.new(214), 314)


func run(t) -> void:
	_cleanup()
	t.current = "checkpoint path security"
	t.check(Persist.valid_world_path(SAVE_PATH), "valid user-data path accepted")
	t.check(Persist.valid_world_path("user://nested/world.json"), "nested world path accepted")
	t.check(not Persist.valid_world_path("res://world.json"), "project resource path rejected")
	t.check(not Persist.valid_world_path("user://../escaped.json"), "parent traversal rejected")
	t.check(not Persist.valid_world_path("user://deep/../../escaped.json"), "nested path escape rejected")
	t.check(not Persist.valid_world_path("user://"), "saving to user-data root rejected")

	var sim = _new_server()
	var point: Vector2 = BarricadeTests.new()._find_place(sim.world)
	t.current = "checkpoint backup creation"
	t.check(point != Vector2.ZERO, "found a valid account-owned world location")
	if point == Vector2.ZERO:
		_cleanup()
		return
	var player = sim.add_player(51, "Owner", "backup-test-account")
	var origin := point + Vector2(-2.8, 0.0)
	player.position = Vector3(origin.x, sim.world.height_at(origin.x, origin.y), origin.y)
	player.inventory.add("wood_1", 4)
	player.inventory.add("stone_1", 2)
	var result: Dictionary = sim.cmd_build(51, point.x, point.y)
	t.check(bool(result.get("ok", false)), "authenticated player constructs a barrier")
	if not result.get("ok", false):
		_cleanup()
		return
	var id: int = int(result["id"])
	t.check(Persist.save(sim, SAVE_PATH), "initial world save succeeds")
	t.check(FileAccess.file_exists(SAVE_PATH), "initial checkpoint exists")
	t.check(not FileAccess.file_exists(SAVE_PATH + ".bak"), "no phantom backup before first replacement")
	var initial: String = _read(SAVE_PATH)
	t.check(not initial.is_empty(), "initial snapshot contains data")
	t.check(not sim.damage_barricade(id, 20.0), "wall can take nonlethal damage")
	t.check(Persist.save(sim, SAVE_PATH), "second save replaces checkpoint")
	t.eq(_read(SAVE_PATH + ".bak"), initial, "backup exactly preserves the previous valid checkpoint")
	var second: String = _read(SAVE_PATH)
	t.check(second != initial, "primary changes after damage")
	var loaded = _new_server()
	t.check(Persist.load(loaded, SAVE_PATH), "newest primary loads normally")
	t.near(float(loaded.barricades[id]["hp"]), 100.0, 0.001, "newest durability recovered")
	var old = _new_server()
	t.check(Persist.load(old, SAVE_PATH + ".bak"), "backup remains a valid independently loadable world")
	t.near(float(old.barricades[id]["hp"]), 120.0, 0.001, "backup represents earlier world state")

	t.current = "backup rotation and strict corruption response"
	t.check(not sim.damage_barricade(id, 15.0), "further damage changes world")
	t.check(Persist.save(sim, SAVE_PATH), "third save rotates backup")
	t.eq(_read(SAVE_PATH + ".bak"), second, "backup rotates to previous complete primary")
	var newest: String = _read(SAVE_PATH)
	t.check(newest != second, "new primary contains further damage")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	t.check(file != null, "can simulate corrupted primary for recovery test")
	if file != null:
		file.store_string("{ invalid JSON")
		file.close()
		t.check(not Persist.load(_new_server(), SAVE_PATH), "corrupted primary must never silently load backup")
		t.eq(_read(SAVE_PATH + ".bak"), second, "corrupted primary does not erase backup")
		t.check(not Persist.save(sim, SAVE_PATH), "saving over invalid primary fails closed instead of replacing backup")
		t.eq(_read(SAVE_PATH + ".bak"), second, "refused save preserves last complete backup")
		var copy_error: Error = DirAccess.copy_absolute(
				ProjectSettings.globalize_path(SAVE_PATH + ".bak"),
				ProjectSettings.globalize_path(SAVE_PATH))
		t.eq(copy_error, OK, "manual administrator recovery can copy backup over primary")
		var restored = _new_server()
		t.check(Persist.load(restored, SAVE_PATH), "explicit backup recovery creates a valid world")
		t.near(float(restored.barricades[id]["hp"]), 100.0, 0.001, "recovered checkpoint is previous state, not silently resurrected newer state")
	_cleanup()
