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
	# Nakama's Lua layer turns an empty array into an empty object: the gateway must hide that.
	var with_lists := character.duplicate(true)
	with_lists["contracts"] = {"active": "", "progress": 0, "completed": [], "crate_ids": []}
	await gateway.save_character(uid, with_lists)
	var lists_back: Dictionary = await gateway.load_character(uid)
	check(typeof(lists_back["data"]["contracts"]["completed"]) == TYPE_ARRAY and typeof(lists_back["data"]["contracts"]["crate_ids"]) == TYPE_ARRAY, "empty arrays stay arrays through Nakama")
	await gateway.save_character(uid, character)
	character["kills"] = 12
	await gateway.save_character(uid, character)
	check((await gateway.load_character(uid))["data"]["kills"] == 12, "saving again overwrites")

	# Conditional writes must not allow stale server snapshots to overwrite characters.
	var version_before: String = str(gateway._versions[uid])
	check(version_before != "" and version_before != "*", "a saved character has a version")
	var stale_save = await player_client.rpc_async_with_key("albion_http_key", "character_save", JSON.stringify({
		"user_id": uid, "version": "*",
		"data": {"json": JSON.stringify({"version": 1, "kills": 99999})},
	}))
	var stale_result: Variant = JSON.parse_string(stale_save.payload) if not stale_save.is_exception() else {}
	check(not bool(stale_result.get("ok", false)), "a stale create-only save is rejected")
	check((await gateway.load_character(uid))["data"]["kills"] == 12, "rejected save leaves the old character intact")

	# A batch contains both character documents and a one-time receipt. No
	# partial transfer may survive a conflict in either character version.
	var second_session = await player_client.authenticate_device_async(
		"test-pair-%d" % Time.get_ticks_usec(), "Buyer%d" % (Time.get_ticks_usec() % 100000), true
	)
	check(not second_session.is_exception(), "second test account signs in")
	if second_session.is_exception():
		_done()
		return
	var other_id: String = second_session.user_id
	check(not (await gateway.load_character(other_id))["exists"], "second character starts empty")
	var other_doc := {"version": 1, "kills": 1, "inventory": {"slots": [
		{"id": "silver", "count": 70}, {"id": "wood_1", "count": 1}
	]}}
	check(await gateway.save_character(other_id, other_doc), "second character is initialized")
	var saved_version_a: String = str(gateway._versions[uid])
	var saved_version_b: String = str(gateway._versions[other_id])
	var pair_a: Dictionary = character.duplicate(true)
	pair_a["kills"] = 15
	var pair_b: Dictionary = other_doc.duplicate(true)
	pair_b["kills"] = 5
	var tx_id := "test-pair-%d" % Time.get_ticks_usec()
	var pair_result: Dictionary = await gateway.save_character_pair(uid, pair_a, other_id, pair_b, tx_id)
	check(pair_result.get("ok", false) and not pair_result.get("replayed", true),
		"two characters and receipt commit together")
	var pair_read_a: Dictionary = await gateway.load_character(uid)
	var pair_read_b: Dictionary = await gateway.load_character(other_id)
	check(pair_read_a["data"]["kills"] == 15 and pair_read_b["data"]["kills"] == 5,
		"both character snapshots persisted")
	var retry: Dictionary = await gateway.save_character_pair(uid, pair_a, other_id, pair_b, tx_id)
	check(retry.get("ok", false) and retry.get("replayed", false),
		"identical pair transaction ID returns the committed receipt")
	var altered: Dictionary = pair_a.duplicate(true)
	altered["kills"] = 8000
	var collision: Dictionary = await gateway.save_character_pair(uid, altered, other_id, pair_b, tx_id)
	check(not collision.get("ok", false) and collision.get("reason", "") == "transaction_id_conflict",
		"receipt ID cannot be reused with different account data")
	# The previous character versions can no longer write. Since Nakama writes
	# the entire batch atomically, neither side can be partially overwritten.
	var stale_pair = await player_client.rpc_async_with_key("albion_http_key", "character_pair_save",
		JSON.stringify({
			"user_a": uid, "user_b": other_id, "version_a": saved_version_a,
			"version_b": saved_version_b, "data_a": {"json": JSON.stringify(altered)},
			"data_b": {"json": JSON.stringify(other_doc)},
			"transaction_id": "stale-pair-%d" % Time.get_ticks_usec(),
		}))
	var stale_pair_result: Variant = JSON.parse_string(stale_pair.payload) if not stale_pair.is_exception() else {}
	check(not stale_pair_result.get("ok", false), "obsolete versions reject the whole settlement")
	check((await gateway.load_character(uid))["data"]["kills"] == 15 and
		(await gateway.load_character(other_id))["data"]["kills"] == 5,
		"failed settlement changes neither stored character")
	var as_player_pair = await player_client.rpc_async(session, "character_pair_save",
		JSON.stringify({"user_a": uid, "user_b": other_id}))
	check(as_player_pair.is_exception(), "players cannot invoke the server-only pair settlement")
	# A successful pair commit updates the version cache used by future autosaves.
	pair_a["kills"] = 16
	check(await gateway.save_character(uid, pair_a), "ordinary versioned save succeeds after a pair commit")
	check((await gateway.load_character(uid))["data"]["kills"] == 16,
		"version-aware autosave follows the committed pair state")
	var original_pair_a: Dictionary = pair_a.duplicate(true)
	original_pair_a["kills"] = 15
	var advanced_replay: Dictionary = await gateway.save_character_pair(
		uid, original_pair_a, other_id, pair_b, tx_id)
	check(not advanced_replay.get("ok", false) and
		advanced_replay.get("reason", "") == "transaction_replay_advanced",
		"an old receipt cannot adopt the version of a newer character snapshot")

	# A player can read their own character document through the normal API, but cannot change it.
	var read = await player_client.read_storage_objects_async(session, [NakamaStorageObjectId.new("character", "main", uid)])
	check(not read.is_exception() and read.objects.size() == 1, "the owner can read the character")
	var tamper = await player_client.write_storage_objects_async(session, [NakamaWriteStorageObject.new("character", "main", 1, 1, JSON.stringify({"kills": 99999}), "")])
	var after: Dictionary = await gateway.load_character(uid)
	check(after["data"]["kills"] == 16, "a player cannot overwrite their own character (still %s)" % str(after["data"]["kills"]))

	# The RPCs refuse to be called with a player session: only the server key holder may save.
	var as_player = await player_client.rpc_async(session, "character_save", JSON.stringify({"user_id": uid, "data": {"kills": 77777}}))
	var guarded: Dictionary = await gateway.load_character(uid)
	check(as_player.is_exception() and guarded["data"]["kills"] == 16, "a player session cannot use the server-only save (kills %s)" % str(guarded["data"]["kills"]))
	var as_player_load = await player_client.rpc_async(session, "character_load", JSON.stringify({"user_id": uid}))
	check(as_player_load.is_exception(), "nor the server-only load")
	var wrong_key = await player_client.rpc_async_with_key("not_the_key", "character_load", JSON.stringify({"user_id": uid}))
	check(wrong_key.is_exception(), "a wrong http key is refused")

	check(await gateway.submit_score(uid, session.username, 16, 3), "submitting a score works")
	var records = await player_client.list_leaderboard_records_async(session, "kills", [uid], null, 5)
	check(not records.is_exception() and records.owner_records.size() == 1 and int(records.owner_records[0].score) == 16, "the score is on the leaderboard")
	_done()


func _done() -> void:
	print("NAKAMA TEST %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
