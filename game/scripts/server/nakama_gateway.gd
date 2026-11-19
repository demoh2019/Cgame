extends Node
## The game server's connection to Nakama: it verifies who a connecting player is and loads and
## saves their character. Everything else about accounts (chat, guilds, friends) the players use
## directly through the Nakama client.

const NakamaScript = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")

var nakama
var client
var http_key := "albion_http_key"
var enabled := false
var saves_in_flight := 0
var save_failures := 0
var _versions: Dictionary = {} # Nakama optimistic storage versions by account.


func setup(host: String, port: int, server_key: String, p_http_key: String, scheme: String = "http") -> void:
	nakama = NakamaScript.new()
	nakama.name = "NakamaClientHost"
	add_child(nakama)
	client = nakama.create_client(server_key, host, port, scheme, 10, NakamaLogger.LOG_LEVEL.ERROR)
	http_key = p_http_key
	enabled = true


## Checks a session token with Nakama itself (the token's signature cannot be checked locally).
## Returns {"ok": true, "user_id", "username"} or {"ok": false, "reason"}.
func verify(token: String, refresh: String = "") -> Dictionary:
	if not enabled:
		return {"ok": false, "reason": "backend_disabled"}
	var session = NakamaSession.new(token, false, refresh)
	if session.is_exception() or session.is_expired():
		return {"ok": false, "reason": "bad_token"}
	var account = await client.get_account_async(session)
	if account.is_exception():
		return {"ok": false, "reason": "rejected"}
	return {"ok": true, "user_id": account.user.id, "username": account.user.username}


## Server-key-only guild lookup. A session may join/leave a guild while
## connected; the game server refreshes these values periodically.
func lookup_guild(user_id: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "reason": "backend_disabled"}
	var response = await client.rpc_async_with_key(http_key, "guild_affiliation",
		JSON.stringify({"user_id": user_id}))
	if response.is_exception():
		return {"ok": false, "reason": "guild_rpc_unavailable"}
	var parsed: Variant = JSON.parse_string(response.payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_guild_response"}
	return parsed


func load_character(user_id: String) -> Dictionary:
	var response = await client.rpc_async_with_key(http_key, "character_load", JSON.stringify({"user_id": user_id}))
	if response.is_exception():
		return {"ok": false, "reason": "rpc_failed"}
	var parsed: Variant = JSON.parse_string(response.payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "bad_response"}
	if not parsed.get("exists", false):
		_versions[user_id] = "*"
		return {"ok": true, "exists": false}
	var version: String = str(parsed.get("version", ""))
	if version.is_empty() or version == "*":
		return {"ok": false, "reason": "missing_version"}
	_versions[user_id] = version
	var data: Variant = parsed.get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": true, "exists": true, "data": {}}
	# New records keep the document as a JSON string, because Nakama's Lua layer turns every empty array
	# into an empty object, which broke saved state that holds empty lists. Older records were stored raw.
	if data.has("json"):
		var document: Variant = JSON.parse_string(str(data["json"]))
		return {"ok": true, "exists": true, "data": document if typeof(document) == TYPE_DICTIONARY else {}}
	return {"ok": true, "exists": true, "data": data}


func save_character(user_id: String, data: Dictionary) -> bool:
	if not _versions.has(user_id):
		save_failures += 1
		push_warning("Refusing to save a character before loading its storage version.")
		return false
	saves_in_flight += 1
	var payload := {
		"user_id": user_id,
		"data": {"json": JSON.stringify(data)},
		"version": str(_versions[user_id]),
	}
	var response = await client.rpc_async_with_key(http_key, "character_save", JSON.stringify(payload))
	saves_in_flight -= 1
	if response.is_exception():
		save_failures += 1
		return false
	var parsed: Variant = JSON.parse_string(response.payload)
	if typeof(parsed) != TYPE_DICTIONARY or not bool(parsed.get("ok", false)):
		save_failures += 1
		return false
	var next_version: String = str(parsed.get("version", ""))
	if next_version.is_empty() or next_version == "*":
		save_failures += 1
		return false
	_versions[user_id] = next_version
	return true


## Durably commit two loaded characters and a unique transaction receipt in
## ONE Nakama storage batch. The caller must exclude concurrent gameplay
## mutations/saves on both accounts for the entire await, otherwise local
## character state may diverge from this transaction.
func save_character_pair(user_a: String, data_a: Dictionary, user_b: String, data_b: Dictionary, transaction_id: String) -> Dictionary:
	if user_a == user_b or not _versions.has(user_a) or not _versions.has(user_b):
		return {"ok": false, "reason": "unloaded_or_identical_accounts"}
	if str(_versions[user_a]) == "*" or str(_versions[user_b]) == "*":
		return {"ok": false, "reason": "characters_not_initialized"}
	var payload := {
		"user_a": user_a, "user_b": user_b,
		"data_a": {"json": JSON.stringify(data_a)},
		"data_b": {"json": JSON.stringify(data_b)},
		"version_a": str(_versions[user_a]),
		"version_b": str(_versions[user_b]),
		"transaction_id": transaction_id,
	}
	saves_in_flight += 1
	var response = await client.rpc_async_with_key(http_key, "character_pair_save", JSON.stringify(payload))
	saves_in_flight -= 1
	if response.is_exception():
		save_failures += 1
		return {"ok": false, "reason": "rpc_failed"}
	var parsed: Variant = JSON.parse_string(response.payload)
	if typeof(parsed) != TYPE_DICTIONARY or not bool(parsed.get("ok", false)):
		save_failures += 1
		return parsed if typeof(parsed) == TYPE_DICTIONARY else {"ok": false, "reason": "bad_response"}
	var version_a: String = str(parsed.get("version_a", ""))
	var version_b: String = str(parsed.get("version_b", ""))
	if version_a.is_empty() or version_b.is_empty():
		save_failures += 1
		return {"ok": false, "reason": "missing_versions"}
	_versions[user_a] = version_a
	_versions[user_b] = version_b
	return {"ok": true, "replayed": bool(parsed.get("replayed", false))}



func submit_score(user_id: String, username: String, kills: int, deaths: int) -> bool:
	var response = await client.rpc_async_with_key(http_key, "leaderboard_submit", JSON.stringify({"user_id": user_id, "username": username, "kills": kills, "deaths": deaths}))
	return not response.is_exception()
