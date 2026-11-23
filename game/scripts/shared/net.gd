extends Node
## The network layer. The same node, with the same name and the same RPC list, exists on the server
## and on every client (Godot needs that), and `role` decides which half of it does anything.

const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
const CaravanEscort = preload("res://scripts/shared/caravan_escort.gd")
const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")
const GuildSiegeLedger = preload("res://scripts/shared/guild_siege_ledger.gd")
const SiegeOutbox = preload("res://scripts/server/siege_outbox.gd")
const SoloCharacterStore = preload("res://scripts/server/solo_character_store.gd")
const TradeJournal = preload("res://scripts/native/trade_journal.gd") # Native CgameTradeJournal when built in.

signal welcomed
signal join_refused(reason: String)
signal result_received(kind: String, data: Dictionary)

var role: String = "client" # "server" or "client"
var shutting_down := false
var sim # GameServer, on the server.
var client # GameClient, on the client.
var allow_debug: bool = false
var _bad_result_packet_warned := false
var _command_counts: Dictionary = {} # peer -> commands in the current second
var _count_clock: float = 0.0
const MAX_COMMANDS_PER_SECOND := 80
var snapshot_accumulator: float = 0.0
var gateway # NakamaGateway, or null in offline mode.
var solo_character_path: String = "" # Local loopback-only server, set by server_main.
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
var trade_journal # TradeJournal: crash-safe redo log of two-account deals, configured by the dedicated server.
const SIEGE_LEDGER_RETRY_SECONDS := 15.0


func _process(delta: float) -> void:
	_count_clock += delta
	if _count_clock >= 1.0:
		_count_clock = 0.0
		_command_counts.clear()
		if role == "server" and sim != null:
			_measure_round_trips()
	if role == "server" and not shutting_down and gateway != null and gateway.enabled:
		# Two-account deals settle in one backend transaction (see GameServer.pair_commits).
		sim.pair_persistence = true
		while not sim.pair_commits.is_empty():
			_commit_pair(sim.pair_commits.pop_front())
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
## ENet smooths each peer's round trip; the server rewinds PvP targets by it (lag compensation).
func _measure_round_trips() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	for id in sim.players:
		var packet_peer: ENetPacketPeer = enet.get_peer(int(id))
		if packet_peer != null:
			sim.peer_round_trip[int(id)] = packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0
	for id in sim.peer_round_trip.keys():
		if not sim.players.has(id):
			sim.peer_round_trip.erase(id)


## Opens the deal journal and replays every deal the backend never confirmed before a crash.
func configure_trade_journal(journal_path: String) -> bool:
	if role != "server" or sim == null or gateway == null or not gateway.enabled or trade_journal != null:
		return false
	var journal = TradeJournal.create()
	if not journal.open_file(journal_path):
		return false
	trade_journal = journal
	if not journal.entries.is_empty():
		# Block those accounts from loading an older backend copy until replay finishes.
		for user in journal.accounts():
			_departing_accounts[user] = true
		call_deferred("_replay_trade_journal")
	return true


func _replay_trade_journal() -> void:
	var blocked: PackedStringArray = trade_journal.accounts()
	for tx in trade_journal.entries.keys():
		var entry: Dictionary = trade_journal.entries[tx]
		var ok := true
		match TradeJournal.replay_kind(entry):
			"pair":
				var result: Dictionary = await gateway.save_character_pair(str(entry["a"]["user"]), entry["a"]["data"],
					str(entry["b"]["user"]), entry["b"]["data"], str(tx))
				ok = bool(result.get("ok", false))
			"single":
				var side: Dictionary = entry["a"] if not bool(entry["a"]["superseded"]) else entry["b"]
				ok = await gateway.save_character(str(side["user"]), side["data"])
		if ok:
			trade_journal.settle(str(tx))
		else:
			push_warning("Deal %s is still unsettled after restart; kept in the journal." % tx)
	for user in blocked:
		_departing_accounts.erase(user)
	print("SERVER trade journal: %d unsettled deals remain" % trade_journal.entries.size())


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
		if not solo_character_path.is_empty():
			# A local solo world must never accept two competing guest IDs.
			if not sim.players.is_empty():
				s_join_refused.rpc_id(peer, "Solo world already has a survivor.")
				_disconnect_later(peer)
				return
			var loaded: Dictionary = SoloCharacterStore.load_character(sim, solo_character_path)
			if not bool(loaded.get("ok", false)):
				s_join_refused.rpc_id(peer, "Solo character save cannot be loaded.")
				_disconnect_later(peer)
				return
			# This is a server-only local owner, never a client-provided ID.
			sim.add_player(peer, str(player_name), "solo-local", loaded["character"])
		else:
			# Public offline guest servers retain their previous unsaved semantics.
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


const PAIR_COMMIT_ATTEMPTS := 6


## Saves both sides of a completed trade or market sale atomically (Nakama character_pair_save). Waits for any save
## of either account in flight, holds both accounts' save slots so no single autosave interleaves, and retries with
## the same transaction ID, which the backend recognises: a commit that did land is never applied twice. Releases the
## two players' deal lock when confirmed; after the last failed attempt the snapshots fall back to the ordinary
## pending saves and the lock is released too, so nobody is stuck.
func _commit_pair(entry: Dictionary) -> void:
	var tx: String = str(entry["tx"])
	var first = sim.players.get(int(entry["a"]))
	var second = sim.players.get(int(entry["b"]))
	if first == null or second == null or first.user_id == "" or second.user_id == "" or first.user_id == second.user_id:
		sim.release_pair_commit(tx) # Offline or guest characters: nothing durable to settle together.
		return
	var user_a: String = first.user_id
	var user_b: String = second.user_id
	while _saving.has(user_a) or _saving.has(user_b):
		await get_tree().process_frame
	_saving[user_a] = true
	_saving[user_b] = true
	# Snapshot after the deal; a later autosave of either account waits for this commit.
	var data_a: Dictionary = sim.character_data(first)
	var data_b: Dictionary = sim.character_data(second)
	# Write-ahead: the deal is on disk before the backend sees it, so a crash can replay it.
	if trade_journal != null and not trade_journal.record(tx, user_a, data_a, user_b, data_b):
		push_warning("Deal %s could not be journaled; settling without crash protection." % tx)
	var committed := false
	for attempt in PAIR_COMMIT_ATTEMPTS:
		var result: Dictionary = await gateway.save_character_pair(user_a, data_a, user_b, data_b, tx)
		if bool(result.get("ok", false)):
			committed = true
			if trade_journal != null:
				trade_journal.settle(tx)
			break
		await get_tree().create_timer(0.5 * float(attempt + 1)).timeout
	_saving.erase(user_a)
	_saving.erase(user_b)
	if not committed:
		_pending_saves[user_a] = data_a
		_pending_saves[user_b] = data_b
		push_warning("Deal %s could not be settled atomically; both characters are queued for retry." % tx)
	sim.release_pair_commit(tx)


## Save writes are serialized by account: an older autosave cannot finish after logout.
func _save_serial(user_id: String, data: Dictionary) -> bool:
	while _saving.has(user_id):
		await get_tree().process_frame
	_saving[user_id] = true
	var ok: bool = await gateway.save_character(user_id, data)
	_saving.erase(user_id)
	if ok and trade_journal != null:
		# This newer state already contains any journaled deal; never replay the older snapshot.
		trade_journal.supersede(user_id)
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
	var solo_saved := true
	if not solo_character_path.is_empty():
		solo_saved = SoloCharacterStore.save_character(sim, solo_character_path, data)
	if user_id != "":
		_departing_accounts[user_id] = true
		if user_to_peer.get(user_id, -1) == peer:
			user_to_peer.erase(user_id)
	sim.remove_player(peer)
	if user_id == "" or gateway == null or not gateway.enabled:
		_departing_accounts.erase(user_id)
		return solo_saved
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
func c_toggle_mount() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "mount", sim.cmd_toggle_mount(peer))


@rpc("any_peer", "reliable")
func c_place_fish_trap() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "place_fish_trap", sim.cmd_place_fish_trap(peer))


@rpc("any_peer", "reliable")
func c_collect_fish_trap(trap_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "collect_fish_trap", sim.cmd_collect_fish_trap(peer, trap_id))


@rpc("any_peer", "reliable")
func c_fish(baited: bool = false, storm_cast: bool = false) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "fish", sim.cmd_fish(peer, baited, storm_cast))


@rpc("any_peer", "reliable")
func c_gather(node_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		var node: Dictionary = sim._find_node(node_id)
		if ResourceGathering.is_strike(str(node.get("kind", ""))):
			s_result.rpc_id(peer, "gather", {"ok": false, "reason": "use_strikes"})
		else:
			s_result.rpc_id(peer, "gather", sim.cmd_gather(peer, node_id))


@rpc("any_peer", "reliable")
func c_resource_pickup(node_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "resource_pickup", sim.cmd_resource_pickup(peer, node_id))


@rpc("any_peer", "reliable")
func c_resource_hit(node_id: int, dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "resource_hit", sim.cmd_resource_hit(peer, node_id, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_craft_from_stash(recipe: String, times: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "craft_stash",
			sim.cmd_craft(peer, str(recipe), times, true))


@rpc("any_peer", "reliable")
func c_enchant(item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "enchant", sim.cmd_enchant(peer, str(item_id)))


@rpc("any_peer", "reliable")
func c_repair_gear() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "repair_gear", sim.cmd_repair_gear(peer))


@rpc("any_peer", "reliable")
func c_alliance(action: String, target_peer: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "alliance", sim.cmd_alliance(peer, str(action), target_peer))


@rpc("any_peer", "reliable")
func c_guild_bank(action: String, item_id: String, quantity: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "guild_bank", sim.cmd_guild_bank(peer, str(action), str(item_id), quantity))


@rpc("any_peer", "reliable")
func c_plant(seed_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "farm", sim.cmd_plant(peer, str(seed_id)))


@rpc("any_peer", "reliable")
func c_harvest() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "farm", sim.cmd_harvest(peer))


@rpc("any_peer", "reliable")
func c_faction(action: String, faction_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "faction", sim.cmd_faction(peer, str(action), str(faction_id)))


@rpc("any_peer", "reliable")
func c_market_bid(item_id: String, quantity: int, unit_price: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_bid(peer, str(item_id), quantity, unit_price))


@rpc("any_peer", "reliable")
func c_market_fill(bid_id: int, quantity: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_fill(peer, bid_id, quantity))


@rpc("any_peer", "reliable")
func c_market_cancel_bid(bid_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "market", sim.cmd_market_cancel_bid(peer, bid_id))


@rpc("any_peer", "reliable")
func c_craft_focus(recipe: String, times: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "craft", sim.cmd_craft(peer, str(recipe), times, false, true))


@rpc("any_peer", "reliable")
func c_craft(recipe: String, times: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "craft", sim.cmd_craft(peer, str(recipe), times))


@rpc("any_peer", "reliable")
func c_survey_ruins() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "survey_ruins", sim.cmd_survey_ruins(peer))


@rpc("any_peer", "reliable")
func c_salvage_gear(item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "salvage_gear", sim.cmd_salvage_gear(peer, str(item_id)))


@rpc("any_peer", "reliable")
func c_dungeon(down: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "dungeon", sim.cmd_dungeon(peer, down))


@rpc("any_peer", "reliable")
func c_build(x: float, z: float, yaw: float = 0.0) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "build", sim.cmd_build(peer, x, z, yaw))


@rpc("any_peer", "reliable")
func c_toggle_door(id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "door", sim.cmd_toggle_door(peer, id))


@rpc("any_peer", "reliable")
func c_build_piece(piece: String, x: float, z: float, facing: float = 0.0) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "build", sim.cmd_build_piece(peer, piece, x, z, facing))



@rpc("any_peer", "reliable")
func c_place_infected_snare(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "infected_snare", sim.cmd_place_infected_snare(peer, x, z))


@rpc("any_peer", "reliable")
func c_throw_flash(direction_x: float, direction_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "throw_flash", sim.cmd_throw_flash(peer, direction_x, direction_z))


@rpc("any_peer", "reliable")
func c_throw_ember(direction_x: float, direction_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "throw_ember",
			sim.cmd_throw_ember(peer, direction_x, direction_z))


@rpc("any_peer", "reliable")
func c_throw_decoy(direction_x: float, direction_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "throw_decoy",
				sim.cmd_throw_decoy(peer, direction_x, direction_z))


@rpc("any_peer", "reliable")
func c_pitch_shelter(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "shelter", sim.cmd_pitch_shelter(peer, x, z))


@rpc("any_peer", "reliable")
func c_pack_shelter(shelter_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "pack_shelter", sim.cmd_pack_shelter(peer, shelter_id))


@rpc("any_peer", "reliable")
func c_light_campfire(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "campfire", sim.cmd_light_campfire(peer, x, z))


@rpc("any_peer", "reliable")
func c_arm_camp_alarm(fire_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "camp_alarm_arm", sim.cmd_arm_camp_alarm(peer, fire_id))


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
func c_expedition_restock(preset_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "expedition_restock",
			sim.cmd_expedition_restock(peer, str(preset_id)))


@rpc("any_peer", "reliable")
func c_equipment_preset(action: String, slot: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "equipment_preset",
			sim.cmd_equipment_preset(peer, str(action), slot))


@rpc("any_peer", "reliable")
func c_stash_bulk() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "stash_bulk", sim.cmd_stash_bulk(peer))


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
func c_caravan(action: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "caravan", sim.cmd_caravan(peer, str(action)))


@rpc("any_peer", "reliable")
func c_contract(action: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "contract", sim.cmd_contract(peer, str(action)))

## The client chooses only a chapter radio action; the server owns every
## stage, branch, evidence check and reward.
@rpc("any_peer", "reliable")
func c_story(action: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "story", sim.cmd_story(peer, str(action)))


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
func c_raid_vote(bag_id: int, choice: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "raid_vote", sim.cmd_raid_vote(peer, bag_id, choice))


@rpc("any_peer", "reliable")
func c_party_loot_mode(mode: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_loot_mode", sim.cmd_party_loot_mode(peer, mode))


@rpc("any_peer", "reliable")
func c_party_focus() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_focus", sim.cmd_party_focus(peer))


@rpc("any_peer", "reliable")
func c_party_ping(x: float, z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_ping", sim.cmd_party_ping(peer, x, z))


@rpc("any_peer", "reliable")
func c_party_corpse_rescue() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "corpse_rescue", sim.cmd_party_corpse_rescue(peer))


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
func c_party_supply_request(need: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_supply_request",
			sim.cmd_party_supply_request(peer, need))


@rpc("any_peer", "reliable")
func c_party_aid(target_id: int, item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_aid", sim.cmd_party_aid(peer, target_id, item_id))


@rpc("any_peer", "reliable")
func c_medic_cover() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "medic_cover", sim.cmd_medic_cover(peer))


@rpc("any_peer", "reliable")
func c_party_provision(target_id: int, kind: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_provision",
			sim.cmd_party_provision(peer, target_id, kind))


@rpc("any_peer", "reliable")
func c_party_triage() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_triage", sim.cmd_party_triage(peer))


@rpc("any_peer", "reliable")
func c_party_kick(target_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party", sim.cmd_party_kick(peer, target_id))


@rpc("any_peer", "reliable")
func c_outpost_provision(site_id: int, request_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "outpost_provision",
			sim.cmd_outpost_provision(peer, site_id, request_id))


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


## Authenticated sender only; no client-supplied medicine or target.
## Only the authenticated player may request food or drink; item stays server-owned.
@rpc("any_peer", "reliable")
func c_smart_provision(intent: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "smart_provision", sim.cmd_smart_provision(peer, intent))


@rpc("any_peer", "reliable")
func c_quick_medicine() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "quick_medicine", sim.cmd_quick_medicine(peer))


@rpc("any_peer", "reliable")
func c_attack(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "attack", sim.cmd_attack(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_party_shield_wall() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "party_shield_wall", sim.cmd_party_shield_wall(peer))


@rpc("any_peer", "reliable")
func c_guardian_intercept(target_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "guardian_intercept", sim.cmd_guardian_intercept(peer, target_id))


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
func c_skill_ultimate(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "skill", sim.cmd_skill(peer, dir_x, dir_z, true))


@rpc("any_peer", "reliable")
func c_gear_skill(slot: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "gear_skill", sim.cmd_gear_skill(peer, str(slot)))


@rpc("any_peer", "reliable")
func c_stagger_finisher() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "stagger_finisher", sim.cmd_stagger_finisher(peer))


@rpc("any_peer", "reliable")
func c_power_attack(dir_x: float, dir_z: float, charge: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "attack", sim.cmd_attack(peer, dir_x, dir_z, charge))


@rpc("any_peer", "reliable")
func c_kick(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "kick", sim.cmd_kick(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_rage() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "rage", sim.cmd_rage(peer))


@rpc("any_peer", "reliable")
func c_parry() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "parry", sim.cmd_parry(peer))


@rpc("any_peer", "reliable")
func c_arcane_bolt(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "arcane_bolt", sim.cmd_arcane_bolt(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_ultimate() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "ultimate", sim.cmd_ultimate(peer))


@rpc("any_peer", "reliable")
func c_dodge(dir_x: float, dir_z: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "dodge", sim.cmd_dodge(peer, dir_x, dir_z))


@rpc("any_peer", "reliable")
func c_loot_sweep() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "loot_sweep", sim.cmd_loot_sweep(peer))


@rpc("any_peer", "reliable")
func c_loot(entity_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "loot", sim.cmd_loot(peer, entity_id))


@rpc("any_peer", "reliable")
func c_raid_claim_selected(entity_id: int, item_id: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "loot", sim.cmd_raid_claim_selected(peer, entity_id, item_id))


@rpc("any_peer", "reliable")
func c_raid_skip_turn(entity_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "raid_skip_turn", sim.cmd_raid_skip_turn(peer, entity_id))


@rpc("any_peer", "reliable")
func c_refill_canteen(boil: bool = false) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "refill_canteen", sim.cmd_refill_canteen(peer, boil))


@rpc("any_peer", "reliable")
func c_sample_spores() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		s_result.rpc_id(peer, "sample_spores", sim.cmd_sample_spores(peer))


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


## Validate result RPC packets before forwarding them to gameplay. The current
## protocol sends (String kind, Dictionary payload); some older servers send a
## single envelope. Do not invent a kind when a legacy packet is ambiguous.
static func normalize_result_packet(kind: Variant, data: Variant = null) -> Dictionary:
	if kind is String and data is Dictionary and not str(kind).is_empty():
		return {"kind": str(kind), "data": data}
	if kind is Dictionary and data == null:
		var envelope: Dictionary = kind
		if envelope.get("kind") is String and not str(envelope["kind"]).is_empty() \
				and envelope.get("data") is Dictionary:
			return {"kind": str(envelope["kind"]), "data": envelope["data"]}
	return {}


@rpc("authority", "reliable")
func s_result(kind: Variant, data: Variant = null) -> void:
	# An optional second parameter lets Object.callp() accept old one-arg
	# replies; valid current two-arg replies retain their original behavior.
	var packet: Dictionary = normalize_result_packet(kind, data)
	if packet.is_empty():
		if not _bad_result_packet_warned:
			_bad_result_packet_warned = true
			push_warning("Incompatible s_result RPC from server: expected command kind and result. " \
				+ "Restart both the Albion After server and client from the same build.")
		return
	var command_kind: String = packet["kind"]
	var payload: Dictionary = packet["data"]
	if client != null:
		client.on_result(command_kind, payload)
	result_received.emit(command_kind, payload)


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
				# The impact is public nearby, but distant thunder should
				# reveal only a coarse weather cell, not the player who
				# caused a strike at their precise coordinates.
				var delivered: Dictionary = event
				if str(event.get("type", "")) == "lightning_struck":
					delivered = _lightning_for_peer(event, peer)
				if not delivered.is_empty():
					personal.append(delivered)
		if not personal.is_empty():
			s_events.rpc_id(peer, personal)
	snapshot_accumulator += delta
	if snapshot_accumulator >= 1.0 / float(Defs.SNAPSHOT_RATE):
		snapshot_accumulator = 0.0
		# One spatial index build for all viewers, not one per connection.
		# Conditional calls retain compatibility with simulated Net fixtures.
		if sim.has_method("prepare_snapshot_interest"):
			sim.prepare_snapshot_interest()
		for peer in sim.players:
			var snap: Dictionary = sim.snapshot_for(peer)
			if not snap.is_empty():
				s_snapshot.rpc_id(peer, snap)
		if sim.has_method("finish_snapshot_interest"):
			sim.finish_snapshot_interest()


## Long-range thunder is atmospheric audio, not a remotely visible
## combat/hazard marker. Exact strike coordinates stay within 90 m.
## Distant listeners receive only a 256 m quantized weather cell and no
## player IDs, damage, warning deadline or precise event radius.
func _lightning_for_peer(event: Dictionary, peer: int) -> Dictionary:
	if sim == null or str(event.get("type", "")) != "lightning_struck" \
			or not event.has("x") or not event.has("z"):
		return {}
	var survivor = sim.players.get(peer)
	if survivor == null or not survivor.position.is_finite():
		return {}
	var x: float = float(event["x"])
	var z: float = float(event["z"])
	if not is_finite(x) or not is_finite(z):
		return {}
	var receiver := Vector2(survivor.position.x, survivor.position.z)
	var strike := Vector2(x, z)
	var d2: float = receiver.distance_squared_to(strike)
	if not is_finite(d2) or d2 > StormLightning.THUNDER_MAX_DISTANCE * \
			StormLightning.THUNDER_MAX_DISTANCE:
		return {}
	if d2 <= Defs.INTEREST_RADIUS * Defs.INTEREST_RADIUS:
		return event
	var grid: float = StormLightning.THUNDER_COARSE_GRID
	return {"type": "distant_thunder",
		"x": float(roundi(x / grid)) * grid,
		"z": float(roundi(z / grid)) * grid}


## Combat sounds and effects are only sent to players close enough to perceive them.
func _is_nearby(event: Dictionary, peer: int) -> bool:
	var player = sim.players.get(peer)
	if player == null or not event.has("x"):
		return false
	return Vector2(player.position.x - float(event["x"]), player.position.z - float(event["z"])).length() <= Defs.INTEREST_RADIUS


func _event_visible_to(event: Dictionary, peer: int) -> bool:
	match event["type"]:
		"story", "story2", "story3", "site_discovered", "caravan_escort_paid", "caravan_defended", "recall_started", "recall_cancelled", "recall_completed", "spawn", "zone", "gathered", "fished", "party_flank", "stealth_ambush", "storm_cast_lost", "crate", "mastery", "renown", "self_defense", "justice", "barricade_shot", "outlaw_bounty", "duel", "arena_queue", "scavenging", "infection", "evaded", "parried", "stagger_finisher", "pvp_honor", "xp", "skill_up", "perk", "party_feast", "party_standard":
			return event.get("peer", -1) == peer
		"camp_alarm":
			# A former ally, distant player, enemy, or recycled peer ID
			# cannot receive camp locations or approximate infected counts.
			if sim == null:
				return false
			var owner_id: int = int(event.get("peer", -1))
			var owner = sim.players.get(owner_id)
			var recipient = sim.players.get(peer)
			if owner == null or recipient == null or not sim._alive(owner) or not sim._alive(recipient):
				return false
			if not recipient.position.is_finite():
				return false
			if Vector2(recipient.position.x - float(event.get("x", INF)),
					recipient.position.z - float(event.get("z", INF))).length_squared() > (
					Defs.INTEREST_RADIUS * Defs.INTEREST_RADIUS):
				return false
			if owner_id == peer:
				return true
			var group: int = int(event.get("group", 0))
			return group > 0 and sim.parties.group_of(owner_id) == group and (
				sim.parties.group_of(peer) == group) and (
				sim.parties.members_of(owner_id).has(peer))
		"caravan_ambushed":
			return sim != null and CaravanEscort.can_receive_alert(
				event, peer, sim.players, sim.parties)
		"party_aid", "party_triage", "medic_cover", "party_provision":
			# Only the caster and actual defender see aggro handoffs.
			return event.get("peer", -1) == peer or event.get("by", -1) == peer
		"party_supply_request":
			# Membership is checked when the event is delivered, not only
			# when it was created: leaving a party revokes location access.
			if sim == null:
				return false
			var source_id: int = int(event.get("peer", -1))
			var group_id: int = int(event.get("group", 0))
			return group_id > 0 and source_id != peer and \
				sim.players.has(source_id) and sim.players.has(peer) and \
				sim.parties.group_of(source_id) == group_id and \
				sim.parties.group_of(peer) == group_id and \
				sim.parties.members_of(source_id).has(peer)
		"trade":
			return event.get("a", -1) == peer or event.get("b", -1) == peer
		"guardian_taunt":
			return _is_nearby(event, peer)
		"guardian_retribution":
			# The earned counterstrike and enemy ID are private to its guardian.
			return event.get("peer", -1) == peer
		"party_shield_wall_block":
			# Only the guardian and the directly shielded victim can see the hit.
			return event.get("peer", -1) == peer or event.get("by", -1) == peer
		"guardian_intercept":
			# Share only with the protected ally and the real guardian.
			return event.get("peer", -1) == peer or event.get("by", -1) == peer
		"outpost_watch":
			# Private outpost distress signal: no remote enemy or third-party feed.
			return sim != null and sim.territory.watch_recipient(peer,
				int(event.get("id", -1)), int(event.get("owner", 0)),
				sim.players, sim.parties, sim.time)
		"outpost_taken", "outpost_lost", "outpost_fortified", "outpost_provisioned", "outpost_breached", \
				"siege_contract_declared", "siege_contract_result":
			return _is_nearby(event, peer)
		"supply_drop":
			return true # Public server-generated announcement.
		"supply_cleared":
			return _is_nearby(event, peer) # Only witnesses receive clearance coordinates.
		"horde_started", "horde_cleared", "horde_expired":
			return _is_nearby(event, peer) # Only local survivors can track this PvP encounter.
		"death":
			return true # Everyone hears that somebody died (no position is shared).
		"hit":
			return event.get("id", -1) == peer or event.get("by", 0) == peer or _is_nearby(event, peer)
		"lightning_struck":
			return not _lightning_for_peer(event, peer).is_empty()
		"lightning_warning", "attack", "siege_charge_armed", "siege_charge_disarmed", "siege_brace_placed", "siege_brace_absorbed", "siege_charge_detonated", "siege_charge_fizzled", "zombie_died", "armor_sunder", "finishing_strike", "decoy_thrown", "ember_thrown", "campfire_doused", "spit_warning", "spit_impact", "siege_started", "raid_started", "raid_warning", "raid_slam", "raid_interrupted", "raid_cone_warning", "raid_cone_struck", "raid_enraged", "raid_reinforcements", "raid_ward_changed", "raid_defeated", "raid_expired":
			return _is_nearby(event, peer)
	return false
