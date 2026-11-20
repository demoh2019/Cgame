extends RefCounted
## A local-only ENet world retains real loot/progression and refuses corrupt
## offline saves. Multiplayer guest servers never acquire this privilege.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const SoloCharacterStore = preload("res://scripts/server/solo_character_store.gd")
const LocalServer = preload("res://scripts/client/local_server.gd")


func _remove(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))


func run(t) -> void:
	var filename := "user://test_solo_%d.json" % Time.get_ticks_usec()
	_remove(filename)
	t.current = "solo save captures real server-owned character data"
	var sim := GameServer.new(WorldGen.new(1313), 1313)
	var player = sim.add_player(47, "Traveler", "solo-local")
	player.inventory.add("wood_1", 9)
	player.stash.add("silver", 20)
	player.survival.hurt(17.0)
	var saved: Dictionary = sim.character_data(player)
	t.check(sim.valid_character_data(saved), "valid server character can be stored")
	t.check(SoloCharacterStore.save_character(sim, filename, saved),
		"single-player progression is committed to disk")
	var loaded: Dictionary = SoloCharacterStore.load_character(sim, filename)
	t.check(bool(loaded.get("ok", false)) and bool(loaded.get("exists", false)),
		"the save can be reloaded in the same world seed")
	if not bool(loaded.get("ok", false)):
		_remove(filename)
		return
	var resumed := GameServer.new(WorldGen.new(1313), 1313)
	var player2 = resumed.add_player(52, "Traveler", "solo-local", loaded["character"])
	t.eq(player2.inventory.count("wood_1"), 9, "gathered resources survive restart")
	t.eq(player2.stash.count("silver"), 20, "protected bank survives restart")
	t.near(player2.survival.health, player.survival.health, 0.0001,
		"character injuries survive restart")
	t.check(player2.id != player.id, "a new ENet peer resumes without sharing the previous peer ID")
	t.current = "malformed saves never become free starter characters"
	var different := GameServer.new(WorldGen.new(42), 42)
	t.eq(SoloCharacterStore.load_character(different, filename).get("reason"), "different_world",
		"wrong world seed cannot import inventory")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["inventory"]["slots"] = [{"id": "wood_1", "count": 999999999}]
	t.check(not SoloCharacterStore.save_character(sim, filename, invalid),
		"invalid stack does not overwrite a legitimate save")
	t.eq(SoloCharacterStore.load_character(sim, filename)["character"]["inventory"],
		saved["inventory"], "rejected modification keeps original inventory")
	t.check(not SoloCharacterStore.save_character(sim, "user://../outside.json", saved),
		"path traversal is rejected")
	t.eq(SoloCharacterStore.load_character(sim, "user://../outside.json").get("reason"),
		"invalid_path", "local player storage never escapes user folder")
	var f: FileAccess = FileAccess.open(filename, FileAccess.WRITE)
	if f != null:
		f.store_string("{garbled")
		f.close()
	t.eq(SoloCharacterStore.load_character(sim, filename).get("reason"), "invalid_json",
		"corrupt character is not reset into a fresh game")
	t.check(not SoloCharacterStore.save_character(sim, filename, saved),
		"save writer does not silently replace malformed existing character")
	_remove(filename)

	t.current = "only private launchers opt into character persistence"
	var offline_args: PackedStringArray = LocalServer.server_arguments("res://", 24566, false)
	t.check("--solo-character" in offline_args, "local world enables offline character saves")
	t.check("--solo-stop" in offline_args, "local launcher requests a clean server shutdown")
	t.check("--max-clients" in offline_args, "solo world is limited to one player")
	var online_args: PackedStringArray = LocalServer.server_arguments("res://", 24566, true)
	t.check("--nakama" in online_args and not "--solo-character" in online_args,
		"authenticated solo characters keep using Nakama instead of overwriting offline saves")
