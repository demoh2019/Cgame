extends RefCounted
## The client's view of the game: the world it generated from the seed, what the server last said,
## and a predicted position for the local player that is corrected whenever the server answers.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Survival = preload("res://scripts/shared/survival.gd")

signal snapshot_received
signal event_received(event: Dictionary)

var net
var world
var peer_id: int = 0
var welcomed: bool = false
var inventory = Inventory.new()
var stash = Inventory.new(Defs.STASH_SLOTS)
var you: Dictionary = {}
var players: Dictionary = {} # id -> entity from the latest snapshot
var zombies: Dictionary = {}
var barricades: Dictionary = {} # Nearby defenses from the server.
var bags: Dictionary = {}
var depleted: Dictionary = {}
var crates_used: Dictionary = {}
var server_time: float = 0.0
var snapshots_received: int = 0
var events: Array = [] # Recent events, newest last (for the HUD log).
var last_results: Dictionary = {} # command kind -> last result

# Client side prediction.
var predicted: Vector3
var predicted_stamina: float = Defs.MAX_STAMINA
var _seq: int = 0
var _pending: Array = [] # {seq, input, dt}
var correction: Vector3 = Vector3.ZERO # Visual offset that decays, so corrections do not snap.
var yaw: float = 0.0
var total_corrections: int = 0
var worst_error: float = 0.0


func _init(p_net) -> void:
	net = p_net
	net.client = self
	peer_id = 0


func on_welcome(world_seed: int, _tick_rate: int) -> void:
	world = WorldGen.new(world_seed)
	welcomed = true
	peer_id = net.multiplayer.get_unique_id()
	predicted_stamina = Defs.MAX_STAMINA


func on_result(kind: String, data: Dictionary) -> void:
	last_results[kind] = data


func on_events(list: Array) -> void:
	for event in list:
		events.append(event)
		event_received.emit(event)
	while events.size() > 40:
		events.pop_front()


func on_snapshot(snapshot: Dictionary) -> void:
	if world == null:
		return
	snapshots_received += 1
	server_time = float(snapshot["time"])
	you = snapshot["you"]
	if snapshot.has("inventory"):
		inventory.load_dict(snapshot["inventory"])
	if snapshot.has("stash"):
		stash.load_dict(snapshot["stash"])
	players.clear()
	for entity in snapshot["players"]:
		players[entity["id"]] = entity
	zombies.clear()
	for entity in snapshot["zombies"]:
		zombies[entity["id"]] = entity
	bags.clear()
	for entity in snapshot["bags"]:
		bags[entity["id"]] = entity
	# The client predicts movement against the same structure circles as the
	# server, but only the server can create or damage them.
	if snapshot.has("barricades"):
		barricades.clear()
		world.dynamic_blockers.clear()
		for entity in snapshot["barricades"]:
			var id: int = int(entity["id"])
			barricades[id] = entity
			world.add_dynamic_blocker(id, float(entity["x"]), float(entity["z"]), 0.85)
	depleted.clear()
	for id in snapshot["depleted"]:
		depleted[id] = true
	crates_used.clear()
	for id in snapshot["crates_used"]:
		crates_used[id] = true
	_reconcile(snapshot)
	snapshot_received.emit()


func _reconcile(snapshot: Dictionary) -> void:
	var authoritative := Vector3(you["x"], you["y"], you["z"])
	if _pending.is_empty() and _seq == 0:
		predicted = authoritative
		predicted_stamina = float(you.get("stamina", Defs.MAX_STAMINA))
		return
	var ack: int = int(snapshot["ack"])
	while not _pending.is_empty() and int(_pending[0]["seq"]) <= ack:
		_pending.pop_front()
	# Replay pending inputs with the last acknowledged stamina value.
	var replayed := authoritative
	var energy := float(you.get("stamina", Defs.MAX_STAMINA))
	for entry in _pending:
		var replay_input: Dictionary = entry["input"].duplicate()
		var duration: float = float(entry["dt"])
		var moving := Vector2(float(replay_input["x"]), float(replay_input["z"])).length_squared() > 0.00001
		var running := bool(replay_input["sprint"]) and moving and float(replay_input["cargo_factor"]) >= 0.9999
		running = running and Survival.can_sprint_with(energy, float(you.get("hunger", 100.0)),
				float(you.get("thirst", 100.0)), duration)
		replay_input["sprint"] = running
		if running:
			energy = maxf(0.0, energy - Defs.SPRINT_STAMINA_PER_SECOND * duration)
		replayed = Movement.step(world, replayed, replay_input, duration)
	predicted_stamina = energy
	var error := replayed.distance_to(predicted)
	worst_error = maxf(worst_error, error)
	if error > 0.001:
		total_corrections += 1
		if error > 2.5:
			correction = Vector3.ZERO # Too far to smooth: snap.
		else:
			correction += predicted - replayed
	predicted = replayed


## Moves the local player and tells the server. Call once per physics frame.
func send_input(move: Vector2, sprint: bool, face_yaw: float, delta: float) -> void:
	if world == null or not you.has("x") or not bool(you.get("alive", true)):
		return
	_seq += 1
	yaw = face_yaw
	# Prediction uses the same weight calculation as the authoritative server.
	var factor: float = inventory.movement_factor()
	var running := sprint and move.length_squared() > 0.00001 and factor >= 0.9999
	running = running and Survival.can_sprint_with(predicted_stamina,
			float(you.get("hunger", 100.0)), float(you.get("thirst", 100.0)), delta)
	var input := {"x": move.x, "z": move.y, "sprint": running, "cargo_factor": factor}
	predicted = Movement.step(world, predicted, input, delta)
	if running:
		predicted_stamina = maxf(0.0, predicted_stamina - Defs.SPRINT_STAMINA_PER_SECOND * delta)
	# Pending replay needs the original request, not the previous prediction.
	input["sprint"] = sprint
	_pending.append({"seq": _seq, "input": input, "dt": delta})
	if _pending.size() > 120:
		_pending.pop_front()
	net.c_input.rpc_id(1, _seq, move.x, move.y, sprint, face_yaw, delta)


func decay_correction(delta: float) -> void:
	correction = correction.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))


## Where to draw the local player: the prediction plus the fading correction.
func display_position() -> Vector3:
	return predicted + correction


func join(player_name: String, token: String = "", refresh: String = "") -> void:
	net.c_join.rpc_id(1, player_name, token, refresh)


# --- Commands ----------------------------------------------------------------------------------------------

func gather(node_id: int) -> void:
	net.c_gather.rpc_id(1, node_id)


func craft(recipe: String, times: int = 1) -> void:
	net.c_craft.rpc_id(1, recipe, times)


func use_item(item_id: String) -> void:
	net.c_use.rpc_id(1, item_id)


func move_stash(item_id: String, count: int, deposit: bool) -> void:
	net.c_stash.rpc_id(1, item_id, count, deposit)


## Trade ids and revisions originate from server events. No client-side inventory mutation.
func trade_invite(target_id: int) -> void:
	net.c_trade_invite.rpc_id(1, target_id)


func trade_offer(trade_id: int, item_id: String, quantity: int) -> void:
	net.c_trade_offer.rpc_id(1, trade_id, item_id, quantity)


func trade_accept(trade_id: int, revision: int) -> void:
	net.c_trade_accept.rpc_id(1, trade_id, revision)


func trade_cancel(trade_id: int) -> void:
	net.c_trade_cancel.rpc_id(1, trade_id)


func vendor(item_id: String, quantity: int, buy: bool) -> void:
	net.c_vendor.rpc_id(1, item_id, quantity, buy)


func contract(action: String) -> void:
	net.c_contract.rpc_id(1, action)


func attack(direction: Vector2) -> void:
	net.c_attack.rpc_id(1, direction.x, direction.y)


func skill(direction: Vector2) -> void:
	net.c_skill.rpc_id(1, direction.x, direction.y)


func loot(entity_id: int) -> void:
	net.c_loot.rpc_id(1, entity_id)


func build(point: Vector2) -> void:
	if point.is_finite():
		net.c_build.rpc_id(1, point.x, point.y)


func repair(id: int) -> void:
	net.c_repair.rpc_id(1, id)


func upgrade(id: int) -> void:
	net.c_upgrade.rpc_id(1, id)


func dismantle(id: int) -> void:
	net.c_dismantle.rpc_id(1, id)


func nearest_barricade(point: Vector3, radius: float = 3.0) -> int:
	var nearest := -1
	var best := radius
	for structure in barricades.values():
		var d := Vector2(point.x - float(structure["x"]), point.z - float(structure["z"])).length()
		if d < best:
			best = d
			nearest = int(structure["id"])
	return nearest


func drink() -> void:
	net.c_drink.rpc_id(1)


# --- Queries for the UI ---------------------------------------------------------------------------------

## Closest gatherable node (not depleted) within `radius` of a point.
func nearest_node(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	var cell := WorldGen.cell_of(point.x, point.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				if depleted.has(node["id"]):
					continue
				var distance := Vector2(node["x"] - point.x, node["z"] - point.z).length()
				if distance < best_distance:
					best = node
					best_distance = distance
	return best


func nearest_loot(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	for bag in bags.values():
		var distance := Vector2(bag["x"] - point.x, bag["z"] - point.z).length()
		if distance < best_distance:
			best = {"id": bag["id"], "kind": "bag", "x": bag["x"], "z": bag["z"]}
			best_distance = distance
	var cell := WorldGen.cell_of(point.x, point.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for crate in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["crates"]:
				if crates_used.has(crate["id"]):
					continue
				var distance := Vector2(crate["x"] - point.x, crate["z"] - point.z).length()
				if distance < best_distance:
					best = {"id": crate["id"], "kind": "crate", "x": crate["x"], "z": crate["z"]}
					best_distance = distance
	return best
