extends Node
## The network layer. The same node, with the same name and the same RPC list, exists on the server
## and on every client (Godot needs that), and `role` decides which half of it does anything.

const Defs = preload("res://scripts/shared/defs.gd")

signal welcomed
signal join_refused(reason: String)
signal result_received(kind: String, data: Dictionary)

var role: String = "client" # "server" or "client"
var shutting_down := false
var sim # GameServer, on the server.
var client # GameClient, on the client.
var allow_debug: bool = false
var _command_counts: Dictionary = {} # peer -> commands in the current second
var _count_clock: float = 0.0
const MAX_COMMANDS_PER_SECOND := 80
var snapshot_accumulator: float = 0.0
var gateway # NakamaGateway, or null in offline mode.
var user_to_peer: Dictionary = {}
var _joining: Dictionary = {} # Peer -> true, until authentication and loading finish.
var _joining_users: Dictionary = {} # Account -> peer; prevents overlapping sign-ins.
var _departing_accounts: Dictionary = {} # Account -> true, until final save finishes.
var _saving: Dictionary = {} # Account -> true; serialize ALL writes for that account.
var _pending_saves: Dictionary = {} # Account -> final state when Nakama is temporarily unavailable.
var _autosave_running := false
var _save_clock: float = 0.0
const SAVE_INTERVAL := 30.0


func _process(delta: float) -> void:
	_count_clock += delta
	if _count_clock >= 1.0:
		_count_clock = 0.0
		_command_counts.clear()


## False if this peer is sending too many commands (a basic flood guard).
func _allowed(peer_id: int) -> bool:
	if role != "server" or sim == null:
		return false
	_command_counts[peer_id] = int(_command_counts.get(peer_id, 0)) + 1
	return int(_command_counts[peer_id]) <= MAX_COMMANDS_PER_SECOND


# --- Client to server ----------------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func c_join(player_name: String, token: String = "", refresh: String = "") -> void:
	if role != "server" or shutting_down:
		return
	var peer := multiplayer.get_remote_sender_id()
	if sim.players.has(peer) or _joining.has(peer):
		return
	if gateway == null or not gateway.enabled:
		# Offline mode: no accounts, nothing is saved.
		sim.add_player(peer, str(player_name))
		s_welcome.rpc_id(peer, sim.world.world_seed, Defs.TICK_RATE)
		return
	_joining[peer] = true
	var identity: Dictionary = await gateway.verify(str(token), str(refresh))
	if not identity.get("ok", false):
		_joining.erase(peer)
		if multiplayer.get_peers().has(peer):
			s_join_refused.rpc_id(peer, "Sign in failed: %s" % identity.get("reason", "rejected"))
			_disconnect_later(peer)
		return
	var user_id: String = str(identity.get("user_id", ""))
	if user_id.is_empty() or _joining_users.has(user_id):
		_joining.erase(peer)
		if multiplayer.get_peers().has(peer):
			s_join_refused.rpc_id(peer, "This account is already signing in.")
			_disconnect_later(peer)
		return
	_joining_users[user_id] = peer
	# The previous character must be fully saved before a new session loads it.
	if user_to_peer.has(user_id):
		var old_peer: int = user_to_peer[user_id]
		var saved_ok: bool = await leave(old_peer)
		_disconnect_later(old_peer)
		if not saved_ok:
			_refuse_join(peer, user_id, "Character save failed. Please retry.")
			return
	# The former peer may have disconnected by itself, leaving a save in progress.
	while _departing_accounts.has(user_id):
		await get_tree().process_frame
	if not multiplayer.get_peers().has(peer):
		_joining_users.erase(user_id)
		_joining.erase(peer)
		return
	# Never load an older character while the last logout is unsaved.
	if _pending_saves.has(user_id):
		var pending: Dictionary = _pending_saves[user_id]
		if not (await _save_serial(user_id, pending)):
			_refuse_join(peer, user_id, "Character storage is unavailable. Please retry.")
			return
		_pending_saves.erase(user_id)
	var loaded: Dictionary = await gateway.load_character(user_id)
	if not multiplayer.get_peers().has(peer):
		_joining_users.erase(user_id)
		_joining.erase(peer)
		return
	if not loaded.get("ok", false):
		_refuse_join(peer, user_id, "The character could not be loaded. Please retry.")
		return
	var saved: Dictionary = loaded.get("data", {}) if loaded.get("exists", false) else {}
	# Existing but malformed storage must not silently become a new starter kit.
	if loaded.get("exists", false) and not sim.valid_character_data(saved):
		_refuse_join(peer, user_id, "Stored character is invalid. Contact an administrator.")
		return
	user_to_peer[user_id] = peer
	sim.add_player(peer, str(identity["username"]), user_id, saved)
	_joining_users.erase(user_id)
	_joining.erase(peer)
	s_welcome.rpc_id(peer, sim.world.world_seed, Defs.TICK_RATE)


func _refuse_join(peer: int, user_id: String, reason: String) -> void:
	_joining_users.erase(user_id)
	_joining.erase(peer)
	if multiplayer.get_peers().has(peer):
		s_join_refused.rpc_id(peer, reason)
		_disconnect_later(peer)


func _disconnect_later(peer: int) -> void:
	await get_tree().create_timer(0.3).timeout # Let the refusal message get out first.
	if multiplayer.get_peers().has(peer):
		multiplayer.multiplayer_peer.disconnect_peer(peer)


## Save writes are serialized by account: an older autosave cannot finish after logout.
func _save_serial(user_id: String, data: Dictionary) -> bool:
	while _saving.has(user_id):
		await get_tree().process_frame
	_saving[user_id] = true
	var ok: bool = await gateway.save_character(user_id, data)
	_saving.erase(user_id)
	return ok


## Removes the disconnected player immediately but waits for all older saves before persisting
## the final state. Failed final saves are retained for retry and block a stale character load.
func leave(peer: int) -> bool:
	var player = sim.players.get(peer)
	if player == null:
		return true
	var user_id: String = player.user_id
	var data: Dictionary = sim.character_data(player)
	if user_id != "":
		_departing_accounts[user_id] = true
		if user_to_peer.get(user_id, -1) == peer:
			user_to_peer.erase(user_id)
	sim.remove_player(peer)
	if user_id == "" or gateway == null or not gateway.enabled:
		return true
	var ok: bool = await _save_serial(user_id, data)
	if ok:
		_pending_saves.erase(user_id)
		await gateway.submit_score(user_id, player.name, int(data["kills"]), int(data["deaths"]))
	else:
		_pending_saves[user_id] = data
		push_warning("Character save failed for account %s; the session will stay locked until retry." % user_id)
	_departing_accounts.erase(user_id)
	return ok


func _save_all() -> void:
	if gateway == null or not gateway.enabled or _autosave_running:
		return
	_autosave_running = true
	for peer in sim.players.keys():
		# A disconnect may occur while waiting for a different player's database write.
		var player = sim.players.get(peer)
		if player == null or player.user_id == "" or _departing_accounts.has(player.user_id):
			continue
		var data: Dictionary = sim.character_data(player)
		var ok: bool = await _save_serial(player.user_id, data)
		if ok and data["kills"] > 0:
			await gateway.submit_score(player.user_id, player.name, int(data["kills"]), int(data["deaths"]))
	# Retry failed logout saves even when nobody is currently logged into that account.
	for user_id in _pending_saves.keys():
		if _departing_accounts.has(user_id) or _joining_users.has(user_id):
			continue
		var pending: Dictionary = _pending_saves[user_id]
		if await _save_serial(user_id, pending):
			_pending_saves.erase(user_id)
	_autosave_running = false


## Called for an orderly server stop, including --quit-after.
func shutdown() -> bool:
	shutting_down = true
	var all_saved := true
	for peer in sim.players.keys():
		var ok: bool = await leave(peer)
		if not ok:
			all_saved = false
	for user_id in _pending_saves.keys():
		var pending: Dictionary = _pending_saves[user_id]
		if await _save_serial(user_id, pending):
			_pending_saves.erase(user_id)
		else:
			all_saved = false
	return all_saved

@rpc("any_peer", "unreliable_ordered")
func c_input(seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		sim.submit_input(peer, seq, move_x, move_z, sprint, yaw, dt)


@rpc("any_peer", "reliable")
func c_fish() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "fish", sim.cmd_fish(peer))


@rpc("any_peer", "reliable")
func c_gather(node_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "gather", sim.cmd_gather(peer, node_id))


@rpc("any_peer", "reliable")
func c_craft(recipe: String, times: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "craft", sim.cmd_craft(peer, str(recipe), times))


@rpc("any_peer", "reliable")
func c_build(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "build", sim.cmd_build(peer, x, z))


@rpc("any_peer", "reliable")
func c_repair(structure_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "repair", sim.cmd_repair(peer, structure_id))


@rpc("any_peer", "reliable")
func c_dismantle(structure_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "dismantle", sim.cmd_dismantle(peer, structure_id))


@rpc("any_peer", "reliable")
func c_stash(item_id: String, count: int, deposit: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "stash", sim.cmd_stash(peer, str(item_id), count, deposit))



@rpc("any_peer", "reliable")
func c_rest() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "rest", sim.cmd_rest(peer))


@rpc("any_peer", "reliable")
func c_contract(action: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "contract", sim.cmd_contract(peer, str(action)))


@rpc("any_peer", "reliable")
func c_trade_invite(target_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "trade", sim.cmd_trade_invite(peer, target_id))


@rpc("any_peer", "reliable")
func c_trade_offer(trade_id: int, item_id: String, quantity: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "trade", sim.cmd_trade_offer(peer, trade_id, item_id, quantity))


@rpc("any_peer", "reliable")
func c_trade_accept(trade_id: int, revision: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "trade", sim.cmd_trade_accept(peer, trade_id, revision))


@rpc("any_peer", "reliable")
func c_trade_cancel(trade_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "trade", sim.cmd_trade_cancel(peer, trade_id))


@rpc("any_peer", "reliable")
func c_market_list() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_list(peer))


@rpc("any_peer", "reliable")
func c_market_create(item_id: String, quantity: int, price: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_create(peer, item_id, quantity, price))


@rpc("any_peer", "reliable")
func c_market_buy(listing_id: int, quantity: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_buy(peer, listing_id, quantity))


@rpc("any_peer", "reliable")
func c_market_cancel(listing_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_cancel(peer, listing_id))


@rpc("any_peer", "reliable")
func c_vendor(item_id: String, quantity: int, buy: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "vendor", sim.cmd_vendor(peer, str(item_id), quantity, buy))


@rpc("any_peer", "reliable")
func c_use(item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "use", sim.cmd_use(peer, str(item_id)))


@rpc("any_peer", "reliable")
func c_attack(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "attack", sim.cmd_attack(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_skill(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "skill", sim.cmd_skill(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_dodge(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "dodge", sim.cmd_dodge(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_loot(entity_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "loot", sim.cmd_loot(peer, entity_id))


@rpc("any_peer", "reliable")
func c_drink() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "drink", sim.cmd_drink_water(peer))


# Test hooks: only honoured when the server was started with debug commands.
@rpc("any_peer", "reliable")
func c_debug(command: String, args: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if role != "server" or not allow_debug or not sim.players.has(peer):
		return
	var player = sim.players[peer]
	match command:
		"teleport":
			player.position = Vector3(float(args["x"]), sim.world.height_at(float(args["x"]), float(args["z"])), float(args["z"]))
		"give":
			player.inventory.add(str(args["item"]), int(args["count"]))
			player.dirty_inventory = true
		"zombie":
			var Zombie = load("res://scripts/shared/zombie.gd")
			var zombie = Zombie.new(sim.new_id(), str(args["type"]), Vector3(float(args["x"]), sim.world.height_at(float(args["x"]), float(args["z"])), float(args["z"])))
			sim.zombies[zombie.id] = zombie
		"hurt":
			player.survival.hurt(float(args["amount"]))
			if not player.survival.alive:
				sim._on_player_death(player, -1)


# --- Server to client ----------------------------------------------------------------------------------

@rpc("authority", "reliable")
func s_welcome(world_seed: int, tick_rate: int) -> void:
	if client != null:
		client.on_welcome(world_seed, tick_rate)
	welcomed.emit()


@rpc("authority", "reliable")
func s_join_refused(reason: String) -> void:
	join_refused.emit(reason)


@rpc("authority", "unreliable_ordered")
func s_snapshot(snapshot: Dictionary) -> void:
	if client != null:
		client.on_snapshot(snapshot)


@rpc("authority", "reliable")
func s_events(list: Array) -> void:
	if client != null:
		client.on_events(list)


@rpc("authority", "reliable")
func s_result(kind: String, data: Dictionary) -> void:
	if client != null:
		client.on_result(kind, data)
	result_received.emit(kind, data)


# --- Server tick helper ------------------------------------------------------------------------------------

## Runs one simulation tick and sends what changed. Called by the server main loop.
func server_tick(delta: float) -> void:
	sim.tick(delta)
	_save_clock += delta
	if _save_clock >= SAVE_INTERVAL:
		_save_clock = 0.0
		_save_all()
	var all_events: Array = sim.drain_events()
	for peer in sim.players:
		var personal: Array = []
		for event in all_events:
			if _event_visible_to(event, peer):
				personal.append(event)
		if not personal.is_empty():
			s_events.rpc_id(peer, personal)
	snapshot_accumulator += delta
	if snapshot_accumulator >= 1.0 / float(Defs.SNAPSHOT_RATE):
		snapshot_accumulator = 0.0
		for peer in sim.players:
			var snap: Dictionary = sim.snapshot_for(peer)
			if not snap.is_empty():
				s_snapshot.rpc_id(peer, snap)


## Combat sounds and effects are only sent to players close enough to perceive them.
func _is_nearby(event: Dictionary, peer: int) -> bool:
	var player = sim.players.get(peer)
	if player == null or not event.has("x"):
		return false
	return Vector2(player.position.x - float(event["x"]), player.position.z - float(event["z"])).length() <= Defs.INTEREST_RADIUS


func _event_visible_to(event: Dictionary, peer: int) -> bool:
	match event["type"]:
		"spawn", "zone", "gathered", "fished", "crate":
			return event.get("peer", -1) == peer
		"trade":
			return event.get("a", -1) == peer or event.get("b", -1) == peer
		"death":
			return true # Everyone hears that somebody died (no position is shared).
		"hit":
			return event.get("id", -1) == peer or event.get("by", 0) == peer or _is_nearby(event, peer)
		"attack", "zombie_died":
			return _is_nearby(event, peer)
	return false
