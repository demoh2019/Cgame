extends RefCounted
## One zombie and its brain. The brain is a small state machine: wander, chase the nearest player
## it notices, attack when close, and give up when the player gets away.

const Defs = preload("res://scripts/shared/defs.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const EliteInfected = preload("res://scripts/shared/elite_infected.gd")
const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")

enum State { IDLE, WANDER, CHASE, ATTACK, DEAD, INVESTIGATE }

var id: int
var type: String
var elite: bool = false
var raid_boss: bool = false # Session-only group encounter; never a client-spawnable type.
var raid_enraged: bool = false # Server transitions once at low raid boss health.
var spawn_id: int
var position: Vector3
var yaw: float = 0.0
var health: float
var state: int = State.IDLE
var target_id: int = -1 # Peer id of the player being chased.
var forced_target_id: int = -1 # Server-authorized party guardian.
var forced_target_seconds: float = 0.0
var home: Vector2
var wander_target: Vector2
var last_known_target: Vector2
var investigate_time: float = 0.0
const INVESTIGATE_SECONDS := 4.0
var think_timer: float = 0.0
var attack_timer: float = 0.0
var spit_pending: bool = false # Delayed ground attack, only for "spitter".
var spit_seconds: float = 0.0
var spit_center: Vector2 = Vector2.ZERO
var stuck_time: float = 0.0
var snared_seconds: float = 0.0 # Server-owned root; movement-only, not attack immunity.
var contributors: Dictionary = {} # Server: peer -> time + equipped weapon for PvE assist XP.
var data: Dictionary
var threat: Dictionary = {} # Bounded per-zombie server combat threat; not sent to clients.


func _init(p_id: int, p_type: String, p_position: Vector3, p_spawn_id: int = 0) -> void:
	id = p_id
	type = p_type
	data = Defs.ZOMBIES[p_type]
	health = float(data["health"])
	position = p_position
	home = Vector2(p_position.x, p_position.z)
	wander_target = home
	last_known_target = home
	spawn_id = p_spawn_id


## One-way transformation on server-created enemies. Never shared mutable stats.
func become_elite() -> void:
	if elite or state == State.DEAD:
		return
	data = EliteInfected.empowered_stats(data)
	health = float(data["health"])
	elite = true


func is_alive() -> bool:
	return state != State.DEAD


## Advances the brain. `players` maps peer id to {position: Vector3, alive: bool,
## safe: bool, noise: float, scent: float, firelight: float}. Sound, scent and light are
## server-owned sensory channels revealing noisy or wounded survivors.
## Returns {"hit": peer_id, "damage": float} when the zombie lands a blow, else {}.
func think(world, players: Dictionary, delta: float, rng: RandomNumberGenerator) -> Dictionary:
	if state == State.DEAD:
		return {}
	attack_timer = maxf(attack_timer - delta, 0.0)
	snared_seconds = maxf(0.0, snared_seconds - maxf(0.0, delta))
	Threat.decay(threat, delta)
	forced_target_seconds = maxf(0.0, forced_target_seconds - delta)
	if forced_target_seconds <= 0.0:
		forced_target_id = -1
	think_timer -= delta
	var here := Vector2(position.x, position.z)
	# Resolve a fixed warned location ONCE, even if the chosen target moved
	# away. Actual player damage is decided later by GameServer.
	if type == "spitter" and spit_pending:
		spit_seconds = maxf(0.0, spit_seconds - delta)
		if spit_seconds <= 0.0:
			spit_pending = false
			return {"spit_impact": true, "x": spit_center.x, "z": spit_center.y}
		return {}

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
		State.INVESTIGATE:
			# Do not magically follow a survivor beyond our pursuit leash.
			# Examine the place where they were last tracked, then return home.
			investigate_time = maxf(0.0, investigate_time - delta)
			if investigate_time <= 0.0 or here.distance_to(last_known_target) < 0.8:
				state = State.WANDER
				wander_target = home
				stuck_time = 0.0
			else:
				_move_toward(world, here, last_known_target, float(data["speed"]) * 0.7, delta)
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
				state = State.INVESTIGATE
				investigate_time = INVESTIGATE_SECONDS
				return {}
			last_known_target = target
			if type == "spitter" and AcidSpitter.can_launch(distance):
				state = State.ATTACK
				yaw = atan2(target.x - here.x, target.y - here.y)
				if attack_timer <= 0.0:
					attack_timer = AcidSpitter.COOLDOWN
					spit_pending = true
					spit_seconds = AcidSpitter.WINDUP_SECONDS
					spit_center = target
					return {"spit_warning": true, "x": target.x, "z": target.y}
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


## Only the authoritative server calls this after checking the guardian's party,
## weapon, distance, combat energy and cooldown.
func force_taunt(peer_id: int, seconds: float) -> bool:
	if not is_alive() or peer_id <= 0 or not is_finite(seconds) or seconds <= 0.0 or seconds > 5.0:
		return false
	forced_target_id = peer_id
	forced_target_seconds = seconds
	target_id = peer_id
	state = State.CHASE
	think_timer = 0.0
	investigate_time = 0.0
	Threat.record(threat, peer_id, 30.0)
	return true


func _select_target(players: Dictionary, here: Vector2) -> void:
	# Threat is subordinate only during the short guardian focus.
	# Safe, dead, distant and disconnected taunts are cleared immediately.
	if forced_target_seconds > 0.0 and players.has(forced_target_id):
		var info: Dictionary = players[forced_target_id]
		var at: Vector3 = info.get("position", Vector3.INF)
		if bool(info.get("alive", false)) and not bool(info.get("safe", true)) and 				at.is_finite() and here.distance_to(Vector2(at.x, at.z)) <= float(data["lose"]):
			target_id = forced_target_id
			state = State.CHASE
			investigate_time = 0.0
			return
	forced_target_id = -1
	forced_target_seconds = 0.0
	# Damage-earning attackers within the leash take priority over passive
	# proximity targeting. Invalid, safe, disconnected or distant IDs expire.
	var priority: int = Threat.pick(threat, players, here, float(data["lose"]), target_id)
	if priority != -1:
		target_id = priority
		if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
			state = State.CHASE
			investigate_time = 0.0
		return
	var best := -1
	var best_distance := INF
	for peer_id in players:
		var info: Dictionary = players[peer_id]
		if not info["alive"] or info["safe"]:
			continue
		var p: Vector3 = info["position"]
		var distance := here.distance_to(Vector2(p.x, p.z))
		# Night makes infected more vigilant; cap new detection by pursuit leash.
		# Hearing remains independent of night and is always authoritative.
		var sight_multiplier := clampf(float(info.get("notice_multiplier", 1.0)), 1.0, 1.35)
		# Camouflage applies to sight only; noise and blood scent keep their
		# original independent detection ranges and active targets stay locked.
		var visual_raw: float = float(info.get("visual_signature", 1.0))
		var visual: float = 1.0 if not is_finite(visual_raw) else clampf(visual_raw, 0.35, 1.0)
		var notice := minf(float(data["notice"]) * sight_multiplier * visual,
			float(data["lose"]) - 1.0)
		var hearing := clampf(float(info.get("noise", 0.0)), 0.0, float(data["lose"]) - 1.0)
		# Scent can improve discovery but never expands the pursuit leash,
		# overrides combat threat or bypasses safe/dead player protections.
		var scent_raw: float = float(info.get("scent", 0.0))
		var scent: float = 0.0
		if is_finite(scent_raw):
			scent = clampf(scent_raw, 0.0, float(data["lose"]) - 1.0)
		# Firelight reveals campers independently of camouflage, but not beyond
		# this infected type's pursuit leash or the server's safe-zone rules.
		var firelight_raw: float = float(info.get("firelight", 0.0))
		var firelight: float = 0.0
		if is_finite(firelight_raw):
			firelight = clampf(firelight_raw, 0.0, float(data["lose"]) - 1.0)
		var detect_range := maxf(maxf(notice, hearing), maxf(scent, firelight))
		if distance < best_distance and (distance <= detect_range or peer_id == target_id):
			best = peer_id
			best_distance = distance
	if best != -1:
		target_id = best
		if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
			state = State.CHASE
			investigate_time = 0.0


## Nearby infected share an already acquired target. Pack alerts never bypass
## server-owned safe-zone, life, or leash checks and cannot overwrite active aggro.
func receive_pack_alert(peer_id: int, players: Dictionary) -> bool:
	if state == State.DEAD or state == State.CHASE or state == State.ATTACK:
		return false
	if not players.has(peer_id):
		return false
	var info: Dictionary = players[peer_id]
	if not bool(info.get("alive", false)) or bool(info.get("safe", true)):
		return false
	var survivor: Vector3 = info["position"]
	var target: Vector2 = Vector2(survivor.x, survivor.z)
	if Vector2(position.x, position.z).distance_to(target) > float(data["lose"]):
		return false
	target_id = peer_id
	last_known_target = target
	state = State.CHASE
	think_timer = 0.25
	investigate_time = 0.0
	return true


## An unattended infected may investigate a thrown clattering lure.
## This never steals aggro from a real chase, raid boss or attacker.
func investigate_decoy(site: Vector2) -> bool:
	if not site.is_finite() or state == State.DEAD or raid_boss:
		return false
	if state == State.CHASE or state == State.ATTACK or not threat.is_empty():
		return false
	if Vector2(position.x, position.z).distance_to(site) > float(data["lose"]):
		return false
	# A lure already being investigated must not redirect the zombie to
	# another newly placed lure every AI tick (unbounded ping-pong).
	if state == State.INVESTIGATE:
		return false
	target_id = -1
	last_known_target = site
	investigate_time = INVESTIGATE_SECONDS
	think_timer = 0.25
	state = State.INVESTIGATE
	return true


func _move_toward(world, here: Vector2, goal: Vector2, speed: float, delta: float) -> void:
	if snared_seconds > 0.0:
		stuck_time = 0.0 # A trap cannot be mistaken for a wall to damage.
		return
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


## Server-only trap application; cannot target a boss or expired/dead zombie.
func apply_snare(seconds: float) -> bool:
	if not is_alive() or raid_boss or not is_finite(seconds) or seconds <= 0.0 or seconds > 3.0:
		return false
	snared_seconds = maxf(snared_seconds, seconds)
	stuck_time = 0.0
	return true


func take_damage(amount: float, attacker_id: int = -1) -> bool:
	## Server-confirmed harm only; credit the actual effective damage, so a
	## huge overkill value cannot fabricate an unlimited hate advantage.
	if state == State.DEAD or not is_finite(amount) or amount <= 0.0:
		return false
	Threat.record(threat, attacker_id, minf(health, amount))
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		state = State.DEAD
		spit_pending = false
		spit_seconds = 0.0
		threat.clear()
		return true
	if state == State.IDLE or state == State.WANDER:
		state = State.CHASE
	return false
