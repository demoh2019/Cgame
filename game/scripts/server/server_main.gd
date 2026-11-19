extends SceneTree
## Dedicated server. Run headless:
##   godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565 --seed 1337
## Add --debug-commands to allow the test hooks.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")
const Net = preload("res://scripts/shared/net.gd")
const GATEWAY_PATH := "res://scripts/server/nakama_gateway.gd"

var net
var sim
var peer: ENetMultiplayerPeer
var _clock: float = 0.0
var _stats_clock: float = 0.0
var _ticks: int = 0
var _max_tick_ms: float = 0.0
var _quit_after: float = 0.0
var _uptime: float = 0.0
var _shutting_down := false
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
	var disable_world_save: bool = false
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
		i += 1
	Engine.physics_ticks_per_second = Defs.TICK_RATE
	sim = GameServer.new(WorldGen.new(world_seed), world_seed)
	if not disable_world_save:
		_world_save_path = world_save_override if not world_save_override.is_empty() else "user://albion_after_world_%d.json" % world_seed
		if not _world_save_path.begins_with("user://"):
			printerr("SERVER world checkpoint must reside under user://")
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
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients)
	if error != OK:
		printerr("SERVER could not listen on port %d (error %d)" % [port, error])
		quit(2)
		return
	get_multiplayer().multiplayer_peer = peer
	get_multiplayer().peer_disconnected.connect(func(id: int) -> void:
		net.leave(id)
		print("SERVER peer %d left (%d players)" % [id, sim.players.size()]))
	get_multiplayer().peer_connected.connect(func(id: int) -> void: print("SERVER peer %d connected" % id))
	print("SERVER listening on %d, seed %d, %d ticks/s%s, accounts: %s" % [port, world_seed, Defs.TICK_RATE, ", debug commands on" if net.allow_debug else "", nakama_address if nakama_address != "" else "offline"])


func _physics_process(delta: float) -> bool:
	if _shutting_down:
		return false
	var started := Time.get_ticks_usec()
	net.server_tick(delta)
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
		print("SERVER players=%d zombies=%d bags=%d tick_max=%.2fms" % [sim.players.size(), sim.zombies.size(), sim.bags.size(), _max_tick_ms])
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
