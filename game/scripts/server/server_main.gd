extends SceneTree
## Dedicated server. Run headless:
##   godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565 --seed 1337
## Add --debug-commands to allow the test hooks.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldStore = preload("res://scripts/server/world_store.gd")
const Net = preload("res://scripts/shared/net.gd")
const GATEWAY_PATH := "res://scripts/server/nakama_gateway.gd"

var net
var sim
var peer: ENetMultiplayerPeer
var _clock: float = 0.0
var _stats_clock: float = 0.0
var _world_save_clock: float = 0.0
const WORLD_AUTOSAVE_SECONDS := 20.0
var _ticks: int = 0
var _max_tick_ms: float = 0.0
var _quit_after: float = 0.0
var _uptime: float = 0.0
var _shutting_down := false


func _initialize() -> void:
	var port := 24565
	var world_seed := 1337
	var max_clients := 64
	var nakama_address := "" # host:port of Nakama; empty means offline mode.
	var nakama_http_key := "albion_http_key"
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
		i += 1
	Engine.physics_ticks_per_second = Defs.TICK_RATE
	sim = GameServer.new(WorldGen.new(world_seed), world_seed)
	var world_load: Dictionary = WorldStore.load(sim)
	if not world_load.get("ok", false):
		# Refuse to spawn over a corrupt existing world file; this prevents
		# an automatic save from destroying the recoverable old snapshot.
		printerr("SERVER world restore refused: %s" % str(world_load.get("reason", "unknown")))
		quit(2)
		return
	if world_load.get("exists", false):
		print("SERVER restored %d barricades for seed %d" % [int(world_load["count"]), world_seed])
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
	if _world_save_clock >= WORLD_AUTOSAVE_SECONDS:
		_world_save_clock = 0.0
		if sim.world_dirty and not _save_world():
			printerr("SERVER world autosave failed; dirty state preserved for retry.")
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


func _save_world() -> bool:
	if sim == null or not sim.world_dirty:
		return true
	if not WorldStore.save(sim):
		return false
	sim.world_dirty = false
	return true


func _finish_shutdown() -> void:
	# Persist the world as well as characters; neither can substitute for
	# the other and failures are reported rather than silently accepted.
	var world_saved: bool = _save_world()
	var saved: bool = await net.shutdown()
	if not saved or not world_saved:
		printerr("SERVER shutdown: a character or world save could not be persisted.")
		quit(1)
		return
	quit(0)
