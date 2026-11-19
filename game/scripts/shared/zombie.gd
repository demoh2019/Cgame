extends RefCounted
## One zombie and its brain. The brain is a small state machine: wander, chase the nearest player
## it notices, attack when close, and give up when the player gets away.

const Defs = preload("res://scripts/shared/defs.gd")
const Movement = preload("res://scripts/shared/movement.gd")

enum State { IDLE, WANDER, CHASE, ATTACK, DEAD }

var id: int
var type: String
var spawn_id: int
var position: Vector3
var yaw: float = 0.0
var health: float
var state: int = State.IDLE
var target_id: int = -1 # Peer id of the player being chased.
var home: Vector2
var wander_target: Vector2
var think_timer: float = 0.0
var attack_timer: float = 0.0
var stuck_time: float = 0.0
var data: Dictionary


func _init(p_id: int, p_type: String, p_position: Vector3, p_spawn_id: int = 0) -> void:
	id = p_id
	type = p_type
	data = Defs.ZOMBIES[p_type]
	health = float(data["health"])
	position = p_position
	home = Vector2(p_position.x, p_position.z)
	wander_target = home
	spawn_id = p_spawn_id


func is_alive() -> bool:
	return state != State.DEAD


## Advances the brain. `players` maps peer id to {position: Vector3, alive: bool, safe: bool}.
## Returns {"hit": peer_id, "damage": float} when the zombie lands a blow, else {}.
func think(world, players: Dictionary, delta: float, rng: RandomNumberGenerator) -> Dictionary:
	if state == State.DEAD:
		return {}
	attack_timer = maxf(attack_timer - delta, 0.0)
	think_timer -= delta
	var here := Vector2(position.x, position.z)

	# Pick or drop a target a few times a second, not every tick.
	if think_timer <= 0.0:
		think_timer = 0.25
		_select_target(players, here)

	var result: Dictionary = {}
	match state:
		State.IDLE, State.WANDER:
			if state == State.IDLE:
				if rng.randf() < 0.012:
					wander_target = home + Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
					state = State.WANDER
			else:
				if here.distance_to(wander_target) < 0.8 or stuck_time > 1.2:
					state = State.IDLE
					stuck_time = 0.0
				else:
					_move_toward(world, here, wander_target, float(data["speed"]) * 0.4, delta)
		State.CHASE, State.ATTACK:
			if not players.has(target_id) or not players[target_id]["alive"] or players[target_id]["safe"]:
				target_id = -1
				state = State.IDLE
				return {}
			var target_pos: Vector3 = players[target_id]["position"]
			var target := Vector2(target_pos.x, target_pos.z)
			var distance := here.distance_to(target)
			if distance > float(data["lose"]):
				target_id = -1
				state = State.WANDER
				wander_target = home
				return {}
			if distance <= float(data["attack_range"]):
				state = State.ATTACK
				yaw = atan2(target.x - here.x, target.y - here.y)
				if attack_timer <= 0.0:
					attack_timer = float(data["attack_cooldown"])
					result = {"hit": target_id, "damage": float(data["damage"])}
			else:
				state = State.CHASE
				_move_toward(world, here, target, float(data["speed"]), delta)
	return result


func _select_target(players: Dictionary, here: Vector2) -> void:
	var best := -1
	var best_distance := INF
	var notice := float(data["notice"])
	for peer_id in players:
		var info: Dictionary = players[peer_id]
		if not info["alive"] or info["safe"]:
			continue
		var p: Vector3 = info["position"]
		var distance := here.distance_to(Vector2(p.x, p.z))
		if distance < best_distance and (distance <= notice or peer_id == target_id):
			best = peer_id
			best_distance = distance
	if best != -1:
		target_id = best
		if state == State.IDLE or state == State.WANDER:
			state = State.CHASE


func _move_toward(world, here: Vector2, goal: Vector2, speed: float, delta: float) -> void:
	var direction := goal - here
	if direction.length() < 0.01:
		return
	direction = direction.normalized()
	yaw = atan2(direction.x, direction.y)
	var before := position
	# Zombies use the same movement rules as players, so they are stopped by trees, rocks and deep water.
	position = Movement.move(world, position, direction, speed, delta)
	if before.distance_to(position) < speed * delta * 0.3:
		stuck_time += delta
	else:
		stuck_time = 0.0


func take_damage(amount: float) -> bool:
	## Returns true if the zombie died from it.
	if state == State.DEAD:
		return false
	health -= amount
	if health <= 0.0:
		health = 0.0
		state = State.DEAD
		return true
	if state == State.IDLE or state == State.WANDER:
		state = State.CHASE
	return false
