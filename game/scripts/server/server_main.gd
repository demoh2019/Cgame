extends SceneTree
## Dedicated server. Run headless:
##   godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565 --seed 1337
## Add --debug-commands to allow the test hooks.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")

var net
var sim
var peer: ENetMultiplayerPeer
var _clock: float = 0.0
var _stats_clock: float = 0.0
var _ticks: int = 0
var _max_tick_ms: float = 0.0
var _quit_after: float = 0.0
var _uptime: float = 0.0


func _initialize() -> void:
	var port := 24565
	var world_seed := 1337
	var max_clients := 64
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
			"--quit-after":
				i += 1
				_quit_after = float(args[i])
		i += 1
	Engine.physics_ticks_per_second = Defs.TICK_RATE
	sim = GameServer.new(WorldGen.new(world_seed), world_seed)
	net = Net.new()
	net.name = "Net"
	net.role = "server"
	net.sim = sim
	net.allow_debug = "--debug-commands" in args
	root.add_child(net)
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients)
	if error != OK:
		printerr("SERVER could not listen on port %d (error %d)" % [port, error])
		quit(2)
		return
	get_multiplayer().multiplayer_peer = peer
	get_multiplayer().peer_disconnected.connect(func(id: int) -> void:
		sim.remove_player(id)
		print("SERVER peer %d left (%d players)" % [id, sim.players.size()]))
	get_multiplayer().peer_connected.connect(func(id: int) -> void: print("SERVER peer %d connected" % id))
	print("SERVER listening on %d, seed %d, %d ticks/s%s" % [port, world_seed, Defs.TICK_RATE, ", debug commands on" if net.allow_debug else ""])


func _physics_process(delta: float) -> bool:
	var started := Time.get_ticks_usec()
	net.server_tick(delta)
	_max_tick_ms = maxf(_max_tick_ms, (Time.get_ticks_usec() - started) / 1000.0)
	_ticks += 1
	_uptime += delta
	_stats_clock += delta
	if _stats_clock >= 10.0:
		print("SERVER players=%d zombies=%d bags=%d tick_max=%.2fms" % [sim.players.size(), sim.zombies.size(), sim.bags.size(), _max_tick_ms])
		_stats_clock = 0.0
		_max_tick_ms = 0.0
	if _quit_after > 0.0 and _uptime >= _quit_after:
		print("SERVER stopping after %.0f s" % _uptime)
		return true
	return false
