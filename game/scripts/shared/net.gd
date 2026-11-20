extends Node
## The network layer. The same node, with the same name and the same RPC list, exists on the server
## and on every client (Godot needs that), and `role` decides which half of it does anything.

const Defs = preload("res://scripts/shared/defs.gd")
const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")
const GuildSiegeLedger = preload("res://scripts/shared/guild_siege_ledger.gd")
const SiegeOutbox = preload("res://scripts/server/siege_outbox.gd")

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
const GUILD_REFRESH_SECONDS := 45.0
var _guild_refresh_clock: float = 0.0
var _guild_refresh_running: bool = false
var _siege_ledger_pending: Array[Dictionary] = [] # Journaled event IDs awaiting Nakama confirmation.
var _siege_ledger_unjournaled: Array[Dictionary] = [] # IO failures; retry writing before sending.
var siege_outbox # SiegeOutbox, configured by the dedicated server at startup.
var _siege_ledger_running: bool = false
var _siege_ledger_retry_clock: float = 0.0
var _guild_score_loading: Dictionary = {}
const SIEGE_LEDGER_RETRY_SECONDS := 15.0


func _process(delta: float) -> void:
	_count_clock += delta
	if _count_clock >= 1.0:
		_count_clock = 0.0
		_command_counts.clear()
	if role == "server" and not shutting_down and gateway != null and gateway.enabled:
		_guild_refresh_clock += maxf(0.0, delta)
		if _guild_refresh_clock >= GUILD_REFRESH_SECONDS and not _guild_refresh_running:
			_guild_refresh_clock = 0.0
			_refresh_verified_guilds()
		_siege_ledger_retry_clock += maxf(0.0, delta)
		if _siege_ledger_retry_clock >= SIEGE_LEDGER_RETRY_SECONDS \
				and not _siege_ledger_running and \
				(not _siege_ledger_pending.is_empty() or not _siege_ledger_unjournaled.is_empty()):
			_siege_ledger_retry_clock = 0.0
			_persist_unjournaled_siege_events()
			if not _siege_ledger_pending.is_empty():
				_flush_siege_ledger()


## Memberships can change while a character is online. Only freshly
## authenticated Nakama account IDs are queried, never client-provided guilds.
## On lookup failure guild privileges are cleared rather than kept stale.
func _refresh_verified_guilds() -> void:
	if _guild_refresh_running or gateway == null or not gateway.enabled:
		return
	_guild_refresh_running = true
	for peer_id in sim.players.keys():
		var player = sim.players.get(peer_id)
		if player == null or player.user_id.is_empty() or _departing_accounts.has(player.user_id):
			continue
		var account: String = player.user_id
		var verified: Dictionary = await gateway.lookup_guild(account)
		# A slow RPC may complete after disconnect and peer ID reuse.
		var current = sim.players.get(peer_id)
		if current == null or current.user_id != account:
			continue
		if GuildIdentity.normalize(verified).is_empty():
			sim.set_verified_guild(peer_id, {
				"ok": true, "guild_id": "", "guild_name": "", "rank": -1,
			})
		else:
			sim.set_verified_guild(peer_id, verified)
			_load_guild_siege_score(str(verified.get("guild_id", "")))
	_guild_refresh_running = false


## Load the durable outbox before accepting clients. A malformed or wrong-seed
## journal fails closed so a restart never silently discards a committed win.
func configure_siege_outbox(journal_path: String) -> bool:
	if role != "server" or sim == null or gateway == null or not gateway.enabled:
		return false
	if siege_outbox != null:
		return false
	var journal = SiegeOutbox.new()
	if not journal.open_file(journal_path, int(sim.world.world_seed)):
		return false
	siege_outbox = journal
	_siege_ledger_pending = journal.snapshot()
	if not _siege_ledger_pending.is_empty():
		call_deferred("_flush_siege_ledger")
	return true


## Append a server-generated win to disk before any attempt to send it to
## Nakama. A failed disk write stays in the local retry backlog and is
## *never* sent until it can be journaled with its original event ID.
func _queue_guild_siege_victories(events: Array) -> void:
	if gateway == null or not gateway.enabled:
		return
	for event in events:
		var eligible: Dictionary = GuildSiegeLedger.eligible_victory(event, sim)
		if eligible.is_empty():
			continue
		var record: Dictionary = {
			"guild_id": str(eligible["guild_id"]),
			"event_id": Crypto.new().generate_random_bytes(16).hex_encode(),
			"site": int(eligible["site"]),
			"world_seed": int(eligible["world_seed"]),
		}
		if siege_outbox != null and not siege_outbox.enqueue(record):
			_siege_ledger_unjournaled.append(record)
			push_error("Siege victory could not be journaled; retrying locally before Nakama commit.")
		else:
			_siege_ledger_pending.append(record)
	if not _siege_ledger_unjournaled.is_empty():
		_persist_unjournaled_siege_events()
	if not _siege_ledger_pending.is_empty() and not _siege_ledger_running:
		_siege_ledger_retry_clock = 0.0
		_flush_siege_ledger()


func _persist_unjournaled_siege_events() -> void:
	if siege_outbox == null:
		while not _siege_ledger_unjournaled.is_empty():
			_siege_ledger_pending.append(_siege_ledger_unjournaled.pop_front())
		return
	while not _siege_ledger_unjournaled.is_empty():
		var record: Dictionary = _siege_ledger_unjournaled.front()
		if not siege_outbox.enqueue(record):
			break
		_siege_ledger_pending.append(record)
		_siege_ledger_unjournaled.pop_front()


## Nakama's receipt resolves ambiguous RPC outcomes. Only after success may
## the front event be removed from the disk checkpoint. Failed disk removal
## leaves the original event in place, safe to replay on the next boot.
func _flush_siege_ledger() -> void:
	if _siege_ledger_running or gateway == null or not gateway.enabled:
		return
	_siege_ledger_running = true
	while not _siege_ledger_pending.is_empty():
		var item: Dictionary = _siege_ledger_pending.front()
		var result: Dictionary = await gateway.record_guild_siege_win(
			str(item["guild_id"]), str(item["event_id"]),
			int(item["site"]), int(item["world_seed"]))
		if not bool(result.get("ok", false)):
			push_warning("Nakama guild siege ledger write failed: " + str(result.get("reason", "unknown")))
			break
		var guild_id: String = str(item["guild_id"])
		sim.guild_siege_wins[guild_id] = maxi(
			int(sim.guild_siege_wins.get(guild_id, 0)), int(result.get("wins", 0)))
		if siege_outbox != null and not siege_outbox.acknowledge(str(item["event_id"])):
			push_error("Could not checkpoint siege receipt ACK; retaining event for idempotent replay.")
			break
		_siege_ledger_pending.pop_front()
		_persist_unjournaled_siege_events()
	_siege_ledger_running = false


## Load the historical score when a verified guild member signs in or
## during a periodic membership refresh. Concurrent loads are coalesced.
func _load_guild_siege_score(guild_id: String) -> void:
	if guild_id.is_empty() or gateway == null or not gateway.enabled \
			or _guild_score_loading.has(guild_id):
		return
	_guild_score_loading[guild_id] = true
	var result: Dictionary = await gateway.load_guild_siege_score(guild_id)
	_guild_score_loading.erase(guild_id)
	if bool(result.get("ok", false)):
		sim.guild_siege_wins[guild_id] = maxi(
			int(sim.guild_siege_wins.get(guild_id, 0)), int(result.get("wins", 0)))


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
	# Resolve membership with the server key. An ENet client cannot invent
	# a guild tag, and pending invitations grant no combat protection.
	var verified_guild: Dictionary = await gateway.lookup_guild(user_id)
	if not multiplayer.get_peers().has(peer) or _joining_users.get(user_id, -1) != peer:
		_joining_users.erase(user_id)
		_joining.erase(peer)
		return
	if GuildIdentity.normalize(verified_guild).is_empty():
		_refuse_join(peer, user_id, "Guild verification is unavailable. Please retry.")
		return
	user_to_peer[user_id] = peer
	sim.add_player(peer, str(identity["username"]), user_id, saved)
	sim.set_verified_guild(peer, verified_guild)
	_load_guild_siege_score(str(verified_guild.get("guild_id", "")))
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
	# The server must resolve combat-logout full loot BEFORE serializing
	# the final Nakama character. Otherwise a disconnect could save gear
	# from before the drop, creating both a public bag and a retained copy.
	sim.prepare_disconnect(peer)
	# Ranked duel forfeits must be reflected in the final account save.
	sim._abort_training(peer, "disconnected")
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
	_persist_unjournaled_siege_events()
	var all_saved := _siege_ledger_unjournaled.is_empty()
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
func c_input(seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float, crouch: bool = false) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		sim.submit_input(peer, seq, move_x, move_z, sprint, yaw, dt, crouch)


@rpc("any_peer", "reliable")
func c_fish(baited: bool = false, storm_cast: bool = false) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "fish", sim.cmd_fish(peer, baited, storm_cast))


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
func c_salvage_gear(item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "salvage_gear", sim.cmd_salvage_gear(peer, str(item_id)))


@rpc("any_peer", "reliable")
func c_build(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "build", sim.cmd_build(peer, x, z))



@rpc("any_peer", "reliable")
func c_place_infected_snare(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "infected_snare", sim.cmd_place_infected_snare(peer, x, z))


@rpc("any_peer", "reliable")
func c_throw_decoy(direction_x: float, direction_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "throw_decoy",
				sim.cmd_throw_decoy(peer, direction_x, direction_z))


@rpc("any_peer", "reliable")
func c_light_campfire(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "campfire", sim.cmd_light_campfire(peer, x, z))


@rpc("any_peer", "reliable")
func c_refuel_campfire(fire_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "refuel", sim.cmd_refuel_campfire(peer, fire_id))


@rpc("any_peer", "reliable")
func c_extinguish_campfire(fire_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "extinguish", sim.cmd_extinguish_campfire(peer, fire_id))


@rpc("any_peer", "reliable")
func c_repair(structure_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "repair", sim.cmd_repair(peer, structure_id))


@rpc("any_peer", "reliable")
func c_upgrade(structure_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "upgrade", sim.cmd_upgrade(peer, structure_id))


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
func c_outpost_supplies(site_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "outpost_supplies",
			sim.cmd_outpost_supplies(peer, site_id))


@rpc("any_peer", "reliable")
func c_contract(action: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "contract", sim.cmd_contract(peer, str(action)))


## Party identities are always the RPC sender; the client can only nominate
## a nearby target to invite/kick, never the leader or group identifier.
@rpc("any_peer", "reliable")
func c_arena_queue_join() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "arena_queue", sim.cmd_arena_queue_join(peer))


@rpc("any_peer", "reliable")
func c_arena_queue_leave() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "arena_queue", sim.cmd_arena_queue_leave(peer))


@rpc("any_peer", "reliable")
func c_duel_invite(target_id: int, ranked: bool = false) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "duel", sim.cmd_duel_invite(peer, target_id, ranked))


@rpc("any_peer", "reliable")
func c_duel_accept() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "duel", sim.cmd_duel_accept(peer))


@rpc("any_peer", "reliable")
func c_duel_cancel() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "duel", sim.cmd_duel_cancel(peer))


@rpc("any_peer", "reliable")
func c_party_invite(target_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party", sim.cmd_party_invite(peer, target_id))


@rpc("any_peer", "reliable")
func c_party_accept() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party", sim.cmd_party_accept(peer))


@rpc("any_peer", "reliable")
func c_party_decline() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party", sim.cmd_party_decline(peer))


@rpc("any_peer", "reliable")
func c_party_leave() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party", sim.cmd_party_leave(peer))


@rpc("any_peer", "reliable")
func c_party_ready_start() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_ready", sim.cmd_party_ready_start(peer))


@rpc("any_peer", "reliable")
func c_party_ready_answer(ready: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_ready", sim.cmd_party_ready_answer(peer, ready))


@rpc("any_peer", "reliable")
func c_party_standard() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_standard", sim.cmd_party_standard(peer))


@rpc("any_peer", "reliable")
func c_party_rally() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "rally", sim.cmd_party_rally(peer))


@rpc("any_peer", "reliable")
func c_party_feast(item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_feast", sim.cmd_party_feast(peer, item_id))


@rpc("any_peer", "reliable")
func c_party_aid(target_id: int, item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_aid", sim.cmd_party_aid(peer, target_id, item_id))


@rpc("any_peer", "reliable")
func c_party_kick(target_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party", sim.cmd_party_kick(peer, target_id))


## Only the sender's authoritative party and backpack can reinforce a flag.
@rpc("any_peer", "reliable")
func c_outpost_fortify(site_id: int, request_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "outpost_fortify",
			sim.cmd_outpost_fortify(peer, site_id, request_id))


## Siege damage is calculated exclusively from authoritative party and inventory state.
@rpc("any_peer", "reliable")
func c_outpost_breach(site_id: int, request_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "outpost_breach",
			sim.cmd_outpost_breach(peer, site_id, request_id))


## A session war declaration may only come from the acting peer.
@rpc("any_peer", "reliable")
func c_siege_declare(site_id: int, request_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "siege_declare",
			sim.cmd_siege_declare(peer, site_id, request_id))


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
func c_market_buy(listing_id: int, quantity: int, request_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_buy(peer, listing_id, quantity, request_id))


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
func c_perk(perk_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "perk", sim.cmd_perk(peer, str(perk_id)))


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
func c_guardian_taunt() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "guardian_taunt", sim.cmd_guardian_taunt(peer))


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
func c_refill_canteen() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "refill_canteen", sim.cmd_refill_canteen(peer))


@rpc("any_peer", "reliable")
func c_collect_rain() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "collect_rain", sim.cmd_collect_rain(peer))


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
		"xp":
			sim._award(player, str(args["skill"]), float(args["amount"]))
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
	_queue_guild_siege_victories(all_events)
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
		"recall_started", "recall_cancelled", "recall_completed", "spawn", "zone", "gathered", "fished", "stealth_ambush", "storm_cast_lost", "crate", "mastery", "renown", "self_defense", "justice", "outlaw_bounty", "duel", "arena_queue", "scavenging", "infection", "evaded", "pvp_honor", "xp", "skill_up", "perk", "party_feast", "party_standard":
			return event.get("peer", -1) == peer
		"party_aid":
			return event.get("peer", -1) == peer or event.get("by", -1) == peer
		"trade":
			return event.get("a", -1) == peer or event.get("b", -1) == peer
		"guardian_taunt":
			return _is_nearby(event, peer)
		"outpost_taken", "outpost_lost", "outpost_fortified", "outpost_breached", \
				"siege_contract_declared", "siege_contract_result":
			return _is_nearby(event, peer)
		"supply_drop":
			return true # Public server-generated announcement.
		"supply_cleared":
			return _is_nearby(event, peer) # Only witnesses receive clearance coordinates.
		"death":
			return true # Everyone hears that somebody died (no position is shared).
		"hit":
			return event.get("id", -1) == peer or event.get("by", 0) == peer or _is_nearby(event, peer)
		"attack", "zombie_died", "decoy_thrown", "campfire_doused", "spit_warning", "spit_impact", "siege_started", "raid_started", "raid_warning", "raid_slam", "raid_enraged", "raid_reinforcements", "raid_defeated", "raid_expired":
			return _is_nearby(event, peer)
	return false
