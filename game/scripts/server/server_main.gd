extends SceneTree
## Dedicated server. Run headless:
##   godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565 --seed 1337
## Add --debug-commands to allow the test hooks.

const Defs = preload("res://scripts/shared/defs.gd")
const NetTimeouts = preload("res://scripts/shared/net_timeouts.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const ServerTickGovernor = preload("res://scripts/server/server_tick_governor.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")
const SoloCharacterStore = preload("res://scripts/server/solo_character_store.gd")
const Net = preload("res://scripts/shared/net.gd")
const NetProtocol = preload("res://scripts/shared/net_protocol.gd")
const GATEWAY_PATH := "res://scripts/server/nakama_gateway.gd"

const DataLayers = preload("res://scripts/shared/data_layers.gd")
var layers_override = null # --layers winter,festival | none; null = follow the calendar.
var net
var sim
var peer: ENetMultiplayerPeer
var _clock: float = 0.0
var _stats_clock: float = 0.0
var _tick_governor = ClassDB.instantiate("AdaptiveTickGovernor") if ClassDB.class_exists("AdaptiveTickGovernor") else ServerTickGovernor.new()
var _ticks: int = 0
var _max_tick_ms: float = 0.0
var _quit_after: float = 0.0
var _uptime: float = 0.0
var _shutting_down := false
var _solo_character_path: String = ""
var _solo_stop_path: String = ""
var _solo_save_clock: float = 0.0
const SOLO_SAVE_INTERVAL := 20.0
var _world_save_path: String = ""
var _world_save_clock: float = 0.0
var _saved_world_revision: int = 0
const WORLD_SAVE_INTERVAL := 45.0


func _initialize() -> void:
	var port := 24565
	var world_seed := 1337
	var max_clients := 64
	var nakama_address := "" # host:port of Nakama; empty means offline mode.
	var nakama_http_key := "albion_http_key"
	var world_save_override: String = ""
	var siege_outbox_override: String = ""
	var solo_character_override: String = ""
	var solo_stop_override: String = ""
	var disable_world_save: bool = false
	var adaptive_incidents: bool = true
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--port":
				i += 1
				port = int(args[i])
			"--seed":
				i += 1
				world_seed = int(args[i])
			"--max-clients":
				i += 1
				max_clients = int(args[i])
			"--nakama":
				i += 1
				nakama_address = args[i]
			"--nakama-key":
				i += 1
				nakama_http_key = args[i]
			"--quit-after":
				i += 1
				_quit_after = float(args[i])
			"--world-save":
				i += 1
				if i >= args.size():
					printerr("SERVER --world-save requires a user:// file path")
					quit(2)
					return
				world_save_override = args[i]
			"--no-world-save":
				disable_world_save = true
			"--layers":
				i += 1
				if i < args.size():
					layers_override = DataLayers.parse_override(args[i])
			"--fixed-incidents":
				adaptive_incidents = false
			"--solo-character":
				i += 1
				if i >= args.size():
					printerr("SERVER --solo-character needs a user:// path")
					quit(2)
					return
				solo_character_override = args[i]
			"--solo-stop":
				i += 1
				if i >= args.size():
					printerr("SERVER --solo-stop needs a user:// path")
					quit(2)
					return
				solo_stop_override = args[i]
			"--siege-outbox":
				i += 1
				if i >= args.size():
					printerr("SERVER --siege-outbox requires a user:// file path")
					quit(2)
					return
				siege_outbox_override = args[i]
		i += 1
	if nakama_address.is_empty() and not siege_outbox_override.is_empty():
		printerr("SERVER --siege-outbox requires --nakama")
		quit(2)
		return
	if not solo_character_override.is_empty() and not nakama_address.is_empty():
		printerr("SERVER local solo character and Nakama saves cannot be combined")
		quit(2)
		return
	if not solo_character_override.is_empty() and solo_stop_override.is_empty():
		printerr("SERVER --solo-character requires a graceful --solo-stop path")
		quit(2)
		return
	if not solo_stop_override.is_empty():
		if not WorldPersistence.valid_world_path(solo_stop_override):
			printerr("SERVER invalid local stop signal path")
			quit(2)
			return
		_solo_stop_path = solo_stop_override
	if not solo_character_override.is_empty():
		if not WorldPersistence.valid_world_path(solo_character_override):
			printerr("SERVER invalid offline solo save path")
			quit(2)
			return
		_solo_character_path = solo_character_override
	Engine.physics_ticks_per_second = Defs.TICK_RATE
	_tick_governor.set_enabled(adaptive_incidents)
	sim = GameServer.new(WorldGen.new(world_seed), world_seed)
	sim.data_layers_override = layers_override
	sim.incident_spawn_cap = _tick_governor.get_budget_units()
	if not disable_world_save:
		_world_save_path = world_save_override if not world_save_override.is_empty() else "user://albion_after_world_%d.json" % world_seed
		if not WorldPersistence.valid_world_path(_world_save_path):
			printerr("SERVER world checkpoint must be a normalized file within user://")
			quit(2)
			return
		if FileAccess.file_exists(_world_save_path):
			if not WorldPersistence.load(sim, _world_save_path):
				printerr("SERVER refused invalid world checkpoint: " + _world_save_path)
				quit(3)
				return
			print("SERVER restored %d account-owned barricades" % sim.barricades.size())
		_saved_world_revision = sim.world_structure_revision
	net = Net.new()
	net.name = "Net"
	net.role = "server"
	net.sim = sim
	net.allow_debug = "--debug-commands" in args
	if not _solo_character_path.is_empty():
		var record: Dictionary = SoloCharacterStore.load_character(sim, _solo_character_path)
		if not bool(record.get("ok", false)):
			printerr("SERVER refused invalid offline solo character: " + str(record.get("reason", "unknown")))
			quit(3)
			return
		net.solo_character_path = _solo_character_path
	root.add_child(net)
	if nakama_address != "":
		if not ResourceLoader.exists(GATEWAY_PATH):
			printerr("SERVER Nakama gateway is unavailable: " + GATEWAY_PATH)
			quit(2)
			return
		var gateway = load(GATEWAY_PATH).new()
		gateway.name = "NakamaGateway"
		root.add_child(gateway)
		var parts := nakama_address.split(":")
		gateway.setup(parts[0], int(parts[1]) if parts.size() > 1 else 7350, "albion_after_key", nakama_http_key)
		net.gateway = gateway
		var outbox_path: String = siege_outbox_override if not siege_outbox_override.is_empty() \
			else "user://albion_after_siege_outbox_%d.json" % world_seed
		if not net.configure_siege_outbox(outbox_path):
			printerr("SERVER refused invalid or inaccessible siege outbox: " + outbox_path)
			quit(3)
			return
		print("SERVER siege outbox restored %d unacknowledged guild victories" %
			net._siege_ledger_pending.size())
		var trade_journal_path: String = "user://albion_after_trade_journal_%d.json" % world_seed
		if not net.configure_trade_journal(trade_journal_path):
			printerr("SERVER refused invalid or inaccessible trade journal: " + trade_journal_path)
			quit(3)
			return
	peer = ENetMultiplayerPeer.new()
	if not _solo_stop_path.is_empty():
		# A solo save slot must not be exposed as a public guest server.
		peer.set_bind_ip("127.0.0.1")
		max_clients = 1
	var error := peer.create_server(port, max_clients)
	if error != OK:
		printerr("SERVER could not listen on port %d (error %d)" % [port, error])
		quit(2)
		return
	if not NetProtocol.install(get_multiplayer() as SceneMultiplayer, net,
			Callable(self, "_on_rpc_protocol_rejected")):
		printerr("SERVER could not initialize RPC protocol authentication.")
		peer.close()
		quit(3)
		return
	get_multiplayer().multiplayer_peer = peer
	get_multiplayer().peer_disconnected.connect(func(id: int) -> void:
		net.leave(id)
		print("SERVER peer %d left (%d players)" % [id, sim.players.size()]))
	get_multiplayer().peer_connected.connect(func(id: int) -> void:
		NetTimeouts.apply(peer, id) # Survive a client's first-launch shader/world stall.
		print("SERVER peer %d connected" % id))
	print("SERVER listening on %d, seed %d, %d ticks/s%s, accounts: %s" % [port, world_seed, Defs.TICK_RATE, ", debug commands on" if net.allow_debug else "", nakama_address if nakama_address != "" else "offline"])


func _on_rpc_protocol_rejected(peer_id: int) -> void:
	print("SERVER rejected peer %d: incompatible RPC protocol. Update client and server together." % peer_id)


func _physics_process(delta: float) -> bool:
	if _shutting_down:
		return false
	if not _solo_stop_path.is_empty() and FileAccess.file_exists(_solo_stop_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_solo_stop_path))
		_shutting_down = true
		call_deferred("_finish_shutdown")
		return false
	var started := Time.get_ticks_usec()
	net.server_tick(delta)
	# Measure authoritative simulation/network work separately from optional
	# disk saves; never skip movement, AI, combat or persistence ticks.
	_tick_governor.observe_tick(Time.get_ticks_usec() - started, sim.players.size())
	sim.incident_spawn_cap = _tick_governor.get_budget_units()
	if not _solo_character_path.is_empty() and not sim.players.is_empty():
		_solo_save_clock += maxf(0.0, delta)
		if _solo_save_clock >= SOLO_SAVE_INTERVAL:
			_solo_save_clock = 0.0
			var survivor = sim.players.values()[0]
			if not SoloCharacterStore.save_character(sim, _solo_character_path,
					sim.character_data(survivor)):
				push_error("SERVER could not autosave the solo survivor.")
	_world_save_clock += delta
	if _world_save_path != "" and _world_save_clock >= WORLD_SAVE_INTERVAL:
		_world_save_clock = 0.0
		if sim.world_structure_revision != _saved_world_revision:
			if WorldPersistence.save(sim, _world_save_path):
				_saved_world_revision = sim.world_structure_revision
			else:
				printerr("SERVER failed writing world checkpoint: " + _world_save_path)
	_max_tick_ms = maxf(_max_tick_ms, (Time.get_ticks_usec() - started) / 1000.0)
	_ticks += 1
	_uptime += delta
	_stats_clock += delta
	if _stats_clock >= 10.0:
		var tick_stats: Dictionary = _tick_governor.snapshot()
		var presence_stats: Dictionary = sim.last_population_query_stats
		print("SERVER players=%d zombies=%d bags=%d tick_max=%.2fms sim_p95=%.2fms incident_cap=%d adaptive=%s presence_queries=%d presence_candidates=%d presence_buckets=%d" % [sim.players.size(), sim.zombies.size(), sim.bags.size(), _max_tick_ms,
			tick_stats["tick_p95_ms"], tick_stats["incident_spawn_cap"],
			"ON" if tick_stats["adaptive_enabled"] else "OFF",
			int(presence_stats.get("queries", 0)),
			int(presence_stats.get("candidate_checks", 0)),
			int(presence_stats.get("bucket_lookups", 0))])
		_stats_clock = 0.0
		_max_tick_ms = 0.0
	if _quit_after > 0.0 and _uptime >= _quit_after:
		print("SERVER stopping after %.0f s; flushing character saves" % _uptime)
		_shutting_down = true
		call_deferred("_finish_shutdown")
	return false


func _finish_shutdown() -> void:
	var world_saved: bool = true
	if _world_save_path != "" and sim.world_structure_revision != _saved_world_revision:
		world_saved = WorldPersistence.save(sim, _world_save_path)
	var saved: bool = await net.shutdown()
	if not saved or not world_saved:
		printerr("SERVER shutdown: character or world checkpoint persistence failed.")
		quit(1)
		return
	quit(0)
