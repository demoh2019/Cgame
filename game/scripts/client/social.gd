extends Node
## Chat and guilds, entirely from Nakama: a world chat room, a guild chat, and Nakama groups as guilds.
## The same node serves the HUD and the tests.

const NakamaScript = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")

signal message_received(channel: String, sender: String, text: String)
signal guild_changed

const CHANNEL_ROOM := 1
const CHANNEL_GROUP := 3
const MAX_MESSAGE_LENGTH := 200

var nakama
var client
var session
var socket
var connected := false
var world_channel_id := ""
var guild_channel_id := ""
var guild: Dictionary = {} # {"id", "name"} of the guild the player belongs to.
var _world_room := "world"


## Signs in with a device id (kept in user://) so the same machine is the same account.
func sign_in(host: String, port: int, device_id: String, username: String) -> Dictionary:
	nakama = NakamaScript.new()
	add_child(nakama)
	client = nakama.create_client("albion_after_key", host, port, "http", 6, NakamaLogger.LOG_LEVEL.ERROR)
	session = await client.authenticate_device_async(device_id, username, true)
	if session.is_exception():
		return {"ok": false, "reason": session.get_exception().message}
	return {"ok": true, "token": session.token, "refresh": session.refresh_token, "username": session.username, "user_id": session.user_id}


func start_chat(room_name: String = "world") -> bool:
	if session == null or session.is_exception():
		return false
	_world_room = room_name
	socket = nakama.create_socket_from(client)
	var result = await socket.connect_async(session)
	if result.is_exception():
		return false
	connected = true
	socket.received_channel_message.connect(_on_message)
	socket.closed.connect(func() -> void: connected = false)
	var channel = await socket.join_chat_async(room_name, CHANNEL_ROOM, false, false)
	if channel.is_exception():
		return false
	world_channel_id = channel.id
	await refresh_guild()
	return true


func _on_message(message) -> void:
	var content: Variant = JSON.parse_string(message.content)
	var text := ""
	if typeof(content) == TYPE_DICTIONARY:
		text = str(content.get("msg", ""))
	var label := "guild" if message.channel_id == guild_channel_id and guild_channel_id != "" else "world"
	message_received.emit(label, message.username, text)


static func clean(text: String) -> String:
	return text.strip_edges().substr(0, MAX_MESSAGE_LENGTH)


func say(text: String) -> bool:
	text = clean(text)
	if not connected or world_channel_id == "" or text == "":
		return false
	var ack = await socket.write_chat_message_async(world_channel_id, {"msg": text})
	return not ack.is_exception()


func say_guild(text: String) -> bool:
	text = clean(text)
	if not connected or guild_channel_id == "" or text == "":
		return false
	var ack = await socket.write_chat_message_async(guild_channel_id, {"msg": text})
	return not ack.is_exception()


# --- Guilds -----------------------------------------------------------------------------------------------------

func refresh_guild() -> void:
	guild = {}
	if guild_channel_id != "" and connected:
		await socket.leave_chat_async(guild_channel_id)
	guild_channel_id = ""
	var groups = await client.list_user_groups_async(session, session.user_id)
	if not groups.is_exception():
		for entry in groups.user_groups:
			# State 0 = superadmin, 1 = admin, 2 = member; 3 = join request still pending.
			if int(entry.state) <= 2:
				guild = {"id": entry.group.id, "name": entry.group.name}
				break
	if not guild.is_empty() and connected:
		var channel = await socket.join_chat_async(guild["id"], CHANNEL_GROUP, false, false)
		if not channel.is_exception():
			guild_channel_id = channel.id
	guild_changed.emit()


func create_guild(guild_name: String) -> Dictionary:
	guild_name = guild_name.strip_edges().substr(0, 24)
	if guild_name.length() < 3:
		return {"ok": false, "reason": "name too short"}
	if not guild.is_empty():
		return {"ok": false, "reason": "already in a guild"}
	var group = await client.create_group_async(session, guild_name, "", null, null, true, 100)
	if group.is_exception():
		return {"ok": false, "reason": group.get_exception().message}
	await refresh_guild()
	return {"ok": true, "id": group.id}


func list_guilds(prefix: String = "") -> Array:
	var result = await client.list_groups_async(session, prefix + "%" if prefix != "" else null, 20)
	var guilds: Array = []
	if result.is_exception():
		return guilds
	for g in result.groups:
		guilds.append({"id": g.id, "name": g.name, "members": int(g.edge_count), "open": g.open})
	return guilds


func join_guild(group_id: String) -> Dictionary:
	if not guild.is_empty():
		return {"ok": false, "reason": "already in a guild"}
	var result = await client.join_group_async(session, group_id)
	if result.is_exception():
		return {"ok": false, "reason": result.get_exception().message}
	await refresh_guild()
	return {"ok": not guild.is_empty()}


func leave_guild() -> bool:
	if guild.is_empty():
		return false
	var result = await client.leave_group_async(session, guild["id"])
	await refresh_guild()
	return not result.is_exception()


func guild_members() -> Array:
	var names: Array = []
	if guild.is_empty():
		return names
	var members = await client.list_group_users_async(session, guild["id"])
	if members.is_exception():
		return names
	for entry in members.group_users:
		names.append(entry.user.username)
	return names


func shutdown() -> void:
	if socket != null:
		socket.close()
