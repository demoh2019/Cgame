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


func load_character(user_id: String) -> Dictionary:
	var response = await client.rpc_async_with_key(http_key, "character_load", JSON.stringify({"user_id": user_id}))
	if response.is_exception():
		return {"ok": false, "reason": "rpc_failed"}
	var parsed: Variant = JSON.parse_string(response.payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "bad_response"}
	if not parsed.get("exists", false):
		return {"ok": true, "exists": false}
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
	saves_in_flight += 1
	var response = await client.rpc_async_with_key(http_key, "character_save", JSON.stringify({"user_id": user_id, "data": {"json": JSON.stringify(data)}}))
	saves_in_flight -= 1
	if response.is_exception():
		save_failures += 1
		return false
	return true


func submit_score(user_id: String, username: String, kills: int, deaths: int) -> bool:
	var response = await client.rpc_async_with_key(http_key, "leaderboard_submit", JSON.stringify({"user_id": user_id, "username": username, "kills": kills, "deaths": deaths}))
	return not response.is_exception()
