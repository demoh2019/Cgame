extends Node
## The network layer. The same node, with the same name and the same RPC list, exists on the server
## and on every client (Godot needs that), and `role` decides which half of it does anything.

const Defs = preload("res://scripts/shared/defs.gd")

signal welcomed
signal result_received(kind: String, data: Dictionary)

var role: String = "client" # "server" or "client"
var sim # GameServer, on the server.
var client # GameClient, on the client.
var allow_debug: bool = false
var _command_counts: Dictionary = {} # peer -> commands in the current second
var _count_clock: float = 0.0
const MAX_COMMANDS_PER_SECOND := 80
var snapshot_accumulator: float = 0.0


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
func c_join(player_name: String) -> void:
	if role != "server":
		return
	var peer := multiplayer.get_remote_sender_id()
	if sim.players.has(peer):
		return
	sim.add_player(peer, str(player_name))
	s_welcome.rpc_id(peer, sim.world.world_seed, Defs.TICK_RATE)


@rpc("any_peer", "unreliable_ordered")
func c_input(seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _allowed(peer):
		sim.submit_input(peer, seq, move_x, move_z, sprint, yaw, dt)


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


func _event_visible_to(event: Dictionary, peer: int) -> bool:
	match event["type"]:
		"spawn", "zone", "gathered", "crate":
			return event.get("peer", -1) == peer
		"death":
			return true # Everyone hears that somebody died (no position is shared).
		"hit":
			return event.get("id", -1) == peer or event.get("by", 0) == peer
		"attack":
			return true
	return false
