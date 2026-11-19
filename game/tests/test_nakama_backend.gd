extends SceneTree
## Needs a running Nakama (game/backend/docker-compose.yml):
##   godot --headless --path game --script res://tests/test_nakama_backend.gd
## Exercises the real server: sign-up, token verification, character save and load, leaderboard.

const Gateway = preload("res://scripts/server/nakama_gateway.gd")
const NakamaScript = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")

var failures: Array[String] = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL " + message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gateway := Gateway.new()
	root.add_child(gateway)
	gateway.setup("127.0.0.1", 7350, "albion_after_key", "albion_http_key")
	var player_client = gateway.client

	var device := "test-device-%d" % Time.get_ticks_usec()
	var session = await player_client.authenticate_device_async(device, "Tester%d" % (Time.get_ticks_usec() % 100000), true)
	check(not session.is_exception(), "device sign-up works: %s" % (session.get_exception().message if session.is_exception() else ""))
	if session.is_exception():
		_done()
		return
	var uid: String = session.user_id
	check(uid != "", "the session has a user id")

	var verified: Dictionary = await gateway.verify(session.token, session.refresh_token)
	check(verified["ok"] and verified["user_id"] == uid, "the server verifies a real token: %s" % str(verified))
	var forged: Dictionary = await gateway.verify(session.token.substr(0, session.token.length() - 6) + "AAAAAA", "")
	check(not forged["ok"], "a token with a broken signature is rejected: %s" % str(forged))
	var garbage: Dictionary = await gateway.verify("not-a-token", "")
	check(not garbage["ok"], "garbage is rejected")

	var fresh: Dictionary = await gateway.load_character(uid)
	check(fresh["ok"] and not fresh["exists"], "a new player has no character yet: %s" % str(fresh))
	var character := {"version": 1, "health": 73.5, "hunger": 40.0, "kills": 9, "inventory": {"slots": [{"id": "club_2", "count": 1}, {"id": "silver", "count": 120}], "weapon": "club_2", "armor": ""}}
	check(await gateway.save_character(uid, character), "saving a character works")
	var loaded: Dictionary = await gateway.load_character(uid)
	check(loaded["ok"] and loaded["exists"], "the character exists afterwards")
	check(loaded["data"].get("kills", 0) == 9 and loaded["data"]["inventory"]["weapon"] == "club_2", "the character round-trips: %s" % str(loaded.get("data")))
	check(is_equal_approx(float(loaded["data"].get("health", 0)), 73.5), "numbers survive")
	character["kills"] = 12
	await gateway.save_character(uid, character)
	check((await gateway.load_character(uid))["data"]["kills"] == 12, "saving again overwrites")

	# A player can read their own character document through the normal API, but cannot change it.
	var read = await player_client.read_storage_objects_async(session, [NakamaStorageObjectId.new("character", "main", uid)])
	check(not read.is_exception() and read.objects.size() == 1, "the owner can read the character")
	var tamper = await player_client.write_storage_objects_async(session, [NakamaWriteStorageObject.new("character", "main", 1, 1, JSON.stringify({"kills": 99999}), "")])
	var after: Dictionary = await gateway.load_character(uid)
	check(after["data"]["kills"] == 12, "a player cannot overwrite their own character (still %s)" % str(after["data"]["kills"]))

	# The RPCs refuse to be called with a player session: only the server key holder may save.
	var as_player = await player_client.rpc_async(session, "character_save", JSON.stringify({"user_id": uid, "data": {"kills": 77777}}))
	var guarded: Dictionary = await gateway.load_character(uid)
	check(as_player.is_exception() and guarded["data"]["kills"] == 12, "a player session cannot use the server-only save (kills %s)" % str(guarded["data"]["kills"]))
	var as_player_load = await player_client.rpc_async(session, "character_load", JSON.stringify({"user_id": uid}))
	check(as_player_load.is_exception(), "nor the server-only load")
	var wrong_key = await player_client.rpc_async_with_key("not_the_key", "character_load", JSON.stringify({"user_id": uid}))
	check(wrong_key.is_exception(), "a wrong http key is refused")

	check(await gateway.submit_score(uid, session.username, 12, 3), "submitting a score works")
	var records = await player_client.list_leaderboard_records_async(session, "kills", [uid], null, 5)
	check(not records.is_exception() and records.owner_records.size() == 1 and int(records.owner_records[0].score) == 12, "the score is on the leaderboard")
	_done()


func _done() -> void:
	print("NAKAMA TEST %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
