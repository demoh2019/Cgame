extends RefCounted
## One zombie and its brain. The brain is a small state machine: wander, chase the nearest player
## it notices, attack when close, and give up when the player gets away.

const Defs = preload("res://scripts/shared/defs.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const EliteInfected = preload("res://scripts/shared/elite_infected.gd")
const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WindHearing = preload("res://scripts/shared/wind_hearing.gd")
const InfectedHearing = preload("res://scripts/shared/infected_hearing.gd")
const SunderMark = preload("res://scripts/shared/sunder_mark.gd")
const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")
const InfectedResolve = preload("res://scripts/shared/infected_resolve.gd")
const InfectedSight = preload("res://scripts/shared/infected_sight.gd")
const InfectedMeleeCover = preload("res://scripts/shared/infected_melee_cover.gd")
const NativeSenses = preload("res://scripts/shared/native_infected_senses.gd")
const EffectRules = preload("res://scripts/shared/effect_application_rules.gd")
const InfectedTargetUtility = preload("res://scripts/native/infected_target_utility.gd") # Native CgameUtilityAI when built in.

enum State { IDLE, WANDER, CHASE, ATTACK, DEAD, INVESTIGATE }

var id: int
var type: String
var elite: bool = false
var raid_boss: bool = false # Session-only group encounter; never a client-spawnable type.
var raid_enraged: bool = false # Server transitions once at low raid boss health.
var spawn_id: int
var supply_cache_id: int = -1 # Server-only guardian of a live contested supply cache.
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
# Prevent oscillating between two expired/barely audible world positions.
# This is transient server-only search memory, not a networked actor target.
var _investigated_sound_sites: Array[Vector2] = []
const INVESTIGATE_SECONDS := 4.0
var think_timer: float = 0.0
var ai_selection_allowed: bool = true # Server-only scheduling hint, no effect on attacks/movement.
var _ai_has_selected_once: bool = false
var attack_timer: float = 0.0
var spit_pending: bool = false # Delayed ground attack, only for "spitter".
var spit_seconds: float = 0.0
var spit_center: Vector2 = Vector2.ZERO
var stuck_time: float = 0.0
var snared_seconds: float = 0.0 # Server-owned root; movement-only, not attack immunity.
var perched: bool = false # Waiting up in a tree; drops onto prey (server TreeAmbush).
var stagger_seconds: float = 0.0 # Short PvE-only incapacitation from a confirmed heavy blow.
var melee_blocked: bool = false # Server-observed solid cover between claw and target.
var stagger_resolve_stacks: int = 0 # Number of effective successive server-side staggers.
var stagger_resolve_seconds: float = 0.0 # Window before diminishing returns reset.
var sunder_until: float = 0.0 # Server-time expiry of PvE armor weakness.
var contributors: Dictionary = {} # Server: peer -> time + equipped weapon for PvE assist XP.
# Temperament (Defs.ZOMBIES "behavior"): roamer, hunter or territorial.
var behavior: String = "roamer"
var unseen_seconds: float = 0.0 # Hunter: how long the target has been out of sight.
var _sight_check: float = 0.0
var _native_senses: Variant = null # Lazy per-infected memory; optional on stock Godot.
var _ai_profiler: Variant = null # Opt-in per-infected target selection profiling.
var _ai_trace: Variant = null # Opt-in server-only native target decision trace.
var _ai_lod_staggered: bool = false # Phase only the first distant passive scan.
var _ai_lod_previous_interval: float = 0.0 # Per-infected nominal passive tier; engine stays stateless.
var _passive_crowd_separation: Vector2 = Vector2.ZERO # Server-sampled cosmetic steering; never combat authority.
var _chase_crowd_correction: Vector2 = Vector2.ZERO # Server ORCA correction for pursuit movement only (bounded).
var _chase_avoidance_active: bool = false # True only while the flank-pursuit step moves this infected.
const CHASE_CROWD_CORRECTION_MAX := 0.75 # Never enough to reverse or stall a pursuit.
static var _ai_lod_checked: bool = false
static var _ai_lod_scheduler: Variant = null
var _native_howl_cooldowns: Variant = null # Lazily allocated native event gate for pack howls.
const PACK_HOWL_COOLDOWN_SECONDS := 6.0
var _howl_pending: bool = false
var _howled_at: int = -1 # Howlers scream once per target.
const HUNTER_MEMORY_SECONDS := 6.0 # A hunter keeps coming this long after losing sight of you.
const HUNTER_SEARCH_SECONDS := 10.0 # ...then searches where it last saw you.
const TERRITORY_GRACE := 3.0
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
	behavior = str(data.get("behavior", "roamer"))


## Shared stateless native simulation LOD policy; no allocation per zombie.
## Falls back to existing 0.25-second target scans on stock Godot.
static func _get_ai_lod_scheduler() -> Variant:
	if not _ai_lod_checked:
		_ai_lod_checked = true
		if ClassDB.class_exists("AISimulationLOD2D"):
			_ai_lod_scheduler = ClassDB.instantiate("AISimulationLOD2D")
	return _ai_lod_scheduler


## One-way transformation on server-created enemies. Never shared mutable stats.
func become_elite() -> void:
	if elite or state == State.DEAD:
		return
	data = EliteInfected.empowered_stats(data)
	health = float(data["health"])
	elite = true
	behavior = "hunter" # Champions never let go of their prey.


## Opt-in timing on the authoritative server. Disabled in ordinary gameplay.
## Returns false on stock Godot when this fork's profiler is unavailable.
func enable_ai_profiling(enabled: bool) -> bool:
	if not enabled:
		if _ai_profiler != null:
			_ai_profiler.set_enabled(false)
		return true
	if _ai_profiler == null:
		if not ClassDB.class_exists("AIExecutionProfiler"):
			return false
		_ai_profiler = ClassDB.instantiate("AIExecutionProfiler")
		if _ai_profiler == null:
			return false
	_ai_profiler.set_enabled(true)
	return true


func get_ai_profile_snapshot() -> Dictionary:
	if _ai_profiler == null:
		return {"enabled": false, "total_samples": 0, "categories": {}}
	return _ai_profiler.get_snapshot()


func reset_ai_profile() -> void:
	if _ai_profiler != null:
		_ai_profiler.reset()


## Opt-in trace of authoritative target selection. Source positions and target
## choices must remain on the server. Unavailable on stock Godot.
func enable_ai_trace(enabled: bool) -> bool:
	if not enabled:
		if _ai_trace != null:
			_ai_trace.reset()
			_ai_trace = null
		return true
	if _ai_trace == null:
		if not ClassDB.class_exists("AIBehaviorTrace"):
			return false
		_ai_trace = ClassDB.instantiate("AIBehaviorTrace")
		if _ai_trace != null:
			# History belongs only to explicitly traced infected; normal
			# server mobs keep the zero-allocation disabled path.
			_ai_trace.set_history_capacity(8)
	return _ai_trace != null


func get_ai_trace_snapshot() -> Dictionary:
	if _ai_trace == null:
		return {"enabled": false, "tick_index": 0, "max_steps": 128,
			"truncated": 0, "steps": []}
	var snapshot: Dictionary = _ai_trace.get_snapshot()
	snapshot["enabled"] = true
	return snapshot


func reset_ai_trace() -> void:
	if _ai_trace != null:
		_ai_trace.reset()


## Replay data is private to server operators; never replicate player-related
## trace decisions in public multiplayer snapshots.
func get_ai_trace_history_frames(changes_only: bool = false) -> Array:
	if _ai_trace == null:
		return []
	return _ai_trace.get_history_frames(changes_only)


func get_ai_slowest_trace_nodes(limit: int = 8) -> Array:
	if _ai_trace == null:
		return []
	return _ai_trace.get_slowest_nodes(limit)


## On-demand server-only visualization of the actual GDScript state machine.
## Uses the same plain-data node layout as BehaviorTreeRunner.get_tree_snapshot()
## without claiming that this state machine is a native BehaviorTree.
func get_ai_state_visual_snapshot() -> Dictionary:
	var states := ["IDLE", "WANDER", "CHASE", "ATTACK", "DEAD", "INVESTIGATE"]
	var nodes: Array = [{
		"path": "root",
		"task_class": "ZombieStateMachine",
		"depth": 0,
		"executed": true,
		"status": 0 if state == State.DEAD else 2,
		"duration_usec": 0,
	}]
	for index in states.size():
		var active: bool = state == index
		nodes.append({
			"path": "root/%d" % index,
			"task_class": states[index],
			"depth": 1,
			"executed": active,
			"status": (0 if state == State.DEAD else 2) if active else -1,
			"duration_usec": 0,
		})
	var trace_snapshot: Dictionary = get_ai_trace_snapshot()
	var steps: Array = trace_snapshot.get("steps", [])
	var selection_status := -1
	var selection_time := 0
	if not steps.is_empty():
		var scan: Dictionary = steps[0]
		selection_status = int(scan.get("status", -1))
		selection_time = int(scan.get("duration_usec", 0))
	nodes.append({
		"path": "root/6",
		"task_class": "TargetSelection",
		"depth": 1,
		"executed": not steps.is_empty(),
		"status": selection_status,
		"duration_usec": selection_time,
	})
	return {
		"nodes": nodes,
		"node_count": nodes.size(),
		"truncated": false,
		"trace_truncated": int(trace_snapshot.get("truncated", 0)),
		"trace_enabled": bool(trace_snapshot.get("enabled", false)),
		"tick_index": int(trace_snapshot.get("tick_index", 0)),
	}


## Server-side diagnostic query. Never include this in public game snapshots:
## it exposes AI target identity and last perceived target locations.
func get_ai_debug_snapshot() -> Dictionary:
	return {
		"zombie_id": id,
		"type": type,
		"state": state,
		"target_id": target_id,
		"health": health,
		"last_known_target": last_known_target,
		"investigate_seconds": investigate_time,
		"perception": _native_senses.get_debug_snapshot() if _native_senses != null else {},
		"profiling": get_ai_profile_snapshot(),
		"trace": get_ai_trace_snapshot(),
		"trace_history": get_ai_trace_history_frames(true),
		"slowest_ai_phases": get_ai_slowest_trace_nodes(4),
		"visual_tree": get_ai_state_visual_snapshot(),
		"pack_howl_cooldown_seconds": float(_native_howl_cooldowns.get_remaining(&"pack_howl")) if _native_howl_cooldowns != null else 0.0,
		"native_simulation_lod": _ai_lod_scheduler != null,
		"native_threat_arbitration": Threat.has_native(),
		"target_scan_in_seconds": maxf(0.0, think_timer),
	}


func is_alive() -> bool:
	return state != State.DEAD


## Advances the brain. `players` maps peer id to {position: Vector3, alive: bool,
## safe: bool, noise: float, scent: float, firelight: float}. Sound, scent and light are
## server-owned sensory channels revealing noisy or wounded survivors.
## Returns {"hit": peer_id, "damage": float} when the zombie lands a blow, else {}.
func think(world, players: Dictionary, delta: float, rng: RandomNumberGenerator) -> Dictionary:
	flank_last_step_us = 0
	flank_last_step_candidates = 0
	flank_last_timed_steps = 0
	if state == State.DEAD:
		return {}
	if _ai_trace != null:
		_ai_trace.begin_tick()
	if _native_howl_cooldowns != null:
		_native_howl_cooldowns.advance_time(maxf(delta, 0.0))
	if _native_senses != null:
		_native_senses.advance_time(delta)
	_flank_replan_remaining = maxf(0.0, _flank_replan_remaining - maxf(delta, 0.0))
	melee_blocked = false
	attack_timer = maxf(attack_timer - delta, 0.0)
	snared_seconds = maxf(0.0, snared_seconds - maxf(0.0, delta))
	stagger_resolve_seconds = InfectedResolve.remaining(stagger_resolve_seconds, delta)
	if stagger_resolve_seconds <= 0.0:
		stagger_resolve_stacks = 0
	Threat.decay(threat, delta)
	forced_target_seconds = maxf(0.0, forced_target_seconds - delta)
	if forced_target_seconds <= 0.0:
		forced_target_id = -1
	think_timer -= delta
	# While staggered, infected cannot move, melee attack or finish a spit.
	# All server-owned countdowns above still advance while incapacitated.
	if stagger_seconds > 0.0:
		stagger_seconds = maxf(0.0, stagger_seconds - maxf(0.0, delta))
		if stagger_seconds <= 0.0:
			think_timer = 0.0 # Reevaluate target after recovering.
		return {}
	var here := Vector2(position.x, position.z)
	# Resolve a fixed warned location ONCE, even if the chosen target moved
	# away. Actual player damage is decided later by GameServer.
	if type == "spitter" and spit_pending:
		spit_seconds = maxf(0.0, spit_seconds - delta)
		if spit_seconds <= 0.0:
			spit_pending = false
			return {"spit_impact": true, "x": spit_center.x, "z": spit_center.y}
		return {}

	# The native simulation LOD controls the frequency of eligible scans.
	# For very large crowds, a separate stable time-slot scheduler may defer
	# only nonurgent scans. First contact, combat threat, guardian taunts and
	# overdue work cannot wait; movement and damage never use these slots.
	if think_timer <= 0.0 and (ai_selection_allowed or not _ai_has_selected_once
			or forced_target_seconds > 0.0 or not threat.is_empty()
			or think_timer <= -0.2):
		think_timer = 0.25
		_ai_has_selected_once = true
		if _ai_profiler != null and _ai_profiler.is_enabled():
			_ai_profiler.begin_sample(&"target_selection")
		var trace_token := -1
		if _ai_trace != null:
			trace_token = _ai_trace.begin_step("target_selection", "ZombieTargetSelection")
		var nearest_viewer: float = _select_target(world, players, here)
		if trace_token >= 0:
			_ai_trace.end_step(trace_token, 0 if target_id != -1 else 1)
		# This LOD applies ONLY to unengaged passive acquisition, not the
		# per-frame motion, attack timers, projectile windups, threat decay,
		# boss mechanics or active chase/attack target validation.
		if target_id == -1 and (state == State.IDLE or state == State.WANDER) and not raid_boss:
			var lod: Variant = _get_ai_lod_scheduler()
			if lod != null:
				# Any eligible survivor within the pursuit leash still gets the
				# exact legacy 0.25s scan, including audible gunshots.
				var near_range: float = float(data["lose"])
				var far_range: float = near_range + 24.0
				# Mass Simulation LOD: one native query now composes nominal
				# distance tier, one-time stable ID phase and temporal hysteresis.
				# The authoritative server still owns the per-zombie phase flag
				# and previous interval; no combat or movement cadence changes.
				if lod.has_method("plan_passive_scan"):
					var plan: Vector2 = lod.plan_passive_scan(
						id, nearest_viewer, near_range, far_range,
						_ai_lod_previous_interval, 4.0, _ai_lod_staggered)
					_ai_lod_previous_interval = plan.x
					think_timer = plan.y
					if not _ai_lod_staggered and nearest_viewer > near_range:
						_ai_lod_staggered = true
				else:
					# Stock Godot and older Cgame binaries retain the exact
					# original scalar scheduler and first-scan semantics.
					var nominal: float = float(lod.get_interval(
						nearest_viewer, near_range, far_range))
					if not _ai_lod_staggered and nearest_viewer > near_range:
						think_timer = float(lod.get_staggered_interval(
							id, nearest_viewer, near_range, far_range))
						_ai_lod_staggered = true
					else:
						if lod.has_method("get_hysteretic_interval"):
							nominal = float(lod.get_hysteretic_interval(
								nearest_viewer, near_range, far_range,
								_ai_lod_previous_interval, 4.0))
						think_timer = nominal
					_ai_lod_previous_interval = nominal
		elif target_id != -1:
			# A later passive scan cannot inherit stale LOD during combat.
			_ai_lod_previous_interval = 0.0
		if _ai_profiler != null and _ai_profiler.is_enabled():
			_ai_profiler.end_sample(&"target_selection")

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
			# Continue an already authorized search only while time remains.
			# At most two distinct locations: no unbounded patrol/search loops.
			investigate_time = maxf(0.0, investigate_time - delta)
			if investigate_time <= 0.0:
				state = State.WANDER
				wander_target = home
				stuck_time = 0.0
			elif here.distance_to(last_known_target) < 0.8:
				var next_sound := Vector2.INF
				if _native_senses != null and _investigated_sound_sites.is_empty():
					_investigated_sound_sites.append(last_known_target)
					for event in _native_senses.get_ranked_confirmed_stimuli(1, 8):
						var candidate: Variant = event.get("position", Vector2.INF)
						if not (candidate is Vector2) or not candidate.is_finite() or \
								here.distance_to(candidate) > float(data["lose"]) or \
								world.is_safe(candidate.x, candidate.y) or \
								world.is_water(candidate.x, candidate.y):
							continue
						var visited := false
						for earlier in _investigated_sound_sites:
							if earlier.distance_to(candidate) < 2.0:
								visited = true
								break
						if not visited:
							next_sound = candidate as Vector2
							break
				if next_sound.is_finite():
					last_known_target = next_sound
				else:
					state = State.WANDER
					wander_target = home
					stuck_time = 0.0
			else:
				_move_toward(world, here, last_known_target, float(data["speed"]) * 0.7, delta)
		State.CHASE, State.ATTACK:
			if not players.has(target_id) or not players[target_id]["alive"] or players[target_id]["safe"]:
				# The authoritative player list owns eligibility: a disconnected,
				# dead or safe-zone survivor must not persist as a remembered
				# source while unrelated confirmed events remain available.
				if _native_senses != null and target_id >= 0:
					_native_senses.forget_confirmed_source(target_id)
				target_id = -1
				state = State.IDLE
				return {}
			var target_pos: Vector3 = players[target_id]["position"]
			var target := Vector2(target_pos.x, target_pos.z)
			var distance := here.distance_to(target)
			if distance > float(data["lose"]):
				var lost_target_id: int = target_id
				target_id = -1
				state = State.INVESTIGATE
				_investigated_sound_sites.clear()
				# Per-actor, already-approved sound memory has precedence over
				# louder sounds from another survivor. Never use the escaped
				# player's unobserved CURRENT position or bypass the pursuit leash.
				if _native_senses != null and not _native_senses.remembers_sight():
					var own_sound: Dictionary = _native_senses.best_confirmed_stimulus_for_source_in_radius(
						1, lost_target_id, here, float(data["lose"]))
					if not own_sound.is_empty():
						last_known_target = own_sound["position"]
					elif _native_senses.remembers_sound():
						last_known_target = _native_senses.last_heard_position()
					else:
						# A separately confirmed, more recent sound can remain valid
						# after the strongest ranked sound has expired. This never
						# changes target_id, creates LOS or overrides safe-zone rules.
						var remembered_sound: Dictionary = _native_senses.best_confirmed_stimulus_in_radius(
							1, here, float(data["lose"]))
						if not remembered_sound.is_empty():
							last_known_target = remembered_sound["position"]
				investigate_time = HUNTER_SEARCH_SECONDS if behavior == "hunter" else INVESTIGATE_SECONDS
				return {}
			if behavior == "territorial" and not _in_territory(target) and forced_target_seconds <= 0.0:
				# Guardians drive you off their ground, then walk back to it.
				target_id = -1
				state = State.WANDER
				wander_target = home
				stuck_time = 0.0
				return {}
			if behavior == "hunter":
				_sight_check -= delta
				if _sight_check <= 0.0:
					_sight_check = 0.3
					var clear: bool = InfectedSight.clear_path(world, position, target_pos)
					if clear:
						unseen_seconds = 0.0
						last_known_target = target
					else:
						unseen_seconds += 0.3
					# Native sight memory mirrors only validated server-side raycasts.
					# advance_time(delta) already aged it at the top of this tick.
					# Hunters retain the last OBSERVED position, not the target's
					# current position while the survivor is hidden behind cover.
					if ClassDB.class_exists("AIVisualSensor2D"):
						if _native_senses == null:
							_native_senses = NativeSenses.new()
						_native_senses.record_confirmed_sight(here, target, float(data["lose"]), clear, 0.0, target_id)
						if _native_senses.remembers_sight():
							last_known_target = _native_senses.last_seen_position()
				if unseen_seconds > HUNTER_MEMORY_SECONDS:
					# Lost you: search the last place you were seen.
					target_id = -1
					unseen_seconds = 0.0
					state = State.INVESTIGATE
					investigate_time = HUNTER_SEARCH_SECONDS
					return {}
			if behavior != "hunter":
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
				# A visible or previously alerted survivor is NOT vulnerable
				# to claws through a constructed barricade or ruin wall.
				# Stay in pursuit and use ordinary obstacle-bashing when
				# movement is blocked; never spend the attack cooldown.
				if not InfectedMeleeCover.clear_attack(
						world, position, target_pos, raid_boss):
					melee_blocked = true
					state = State.CHASE
					_move_toward(world, here, target, float(data["speed"]), delta)
				else:
					state = State.ATTACK
					yaw = atan2(target.x - here.x, target.y - here.y)
					if attack_timer <= 0.0:
						attack_timer = float(data["attack_cooldown"])
						result = {"hit": target_id, "damage": float(data["damage"])}
			else:
				state = State.CHASE
				# Only this out-of-reach pursuit step takes the server's ORCA crowd correction;
				# attacks, blocked-claw approach, leaps and the flank goal itself are untouched.
				_chase_avoidance_active = true
				_move_toward(world, here, _flank_goal(here, target), float(data["speed"]), delta)
				_chase_avoidance_active = false
	return result


func _in_territory(point: Vector2) -> bool:
	return point.distance_to(home) <= float(data.get("territory", 18.0)) + TERRITORY_GRACE


## True once when a howler has just spotted someone; the server wakes the pack around it.
func consume_howl() -> bool:
	var pending := _howl_pending
	_howl_pending = false
	if not pending:
		return false
	# The server has already validated a target and authorized the event.
	# Native simulation-time cooldown prevents a howler from waking the pack
	# repeatedly when it switches between several different survivors.
	if _native_howl_cooldowns == null and ClassDB.class_exists("AIActionCooldowns"):
		_native_howl_cooldowns = ClassDB.instantiate("AIActionCooldowns")
	if _native_howl_cooldowns != null:
		return bool(_native_howl_cooldowns.try_trigger(&"pack_howl", PACK_HOWL_COOLDOWN_SECONDS))
	return true # Stock Godot preserves existing one-howl-per-target behavior.


func _note_target_acquired() -> void:
	unseen_seconds = 0.0
	_investigated_sound_sites.clear()
	if data.has("howl_radius") and target_id != -1 and target_id != _howled_at:
		_howled_at = target_id
		_howl_pending = true


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


func _select_target(world, players: Dictionary, here: Vector2) -> float:
	# Threat is subordinate only during the short guardian focus.
	# Safe, dead, distant and disconnected taunts are cleared immediately.
	if forced_target_seconds > 0.0 and players.has(forced_target_id):
		var info: Dictionary = players[forced_target_id]
		var at: Vector3 = info.get("position", Vector3.INF)
		if bool(info.get("alive", false)) and not bool(info.get("safe", true)) and 				at.is_finite() and here.distance_to(Vector2(at.x, at.z)) <= float(data["lose"]):
			target_id = forced_target_id
			state = State.CHASE
			investigate_time = 0.0
			return 0.0
	forced_target_id = -1
	forced_target_seconds = 0.0
	# Damage-earning attackers within the leash take priority over passive
	# proximity targeting. Invalid, safe, disconnected or distant IDs expire.
	var priority: int = Threat.pick(threat, players, here, float(data["lose"]), target_id)
	if priority != -1 and behavior == "territorial":
		var attacker: Vector3 = players[priority].get("position", Vector3.INF)
		if not attacker.is_finite() or not _in_territory(Vector2(attacker.x, attacker.z)):
			priority = -1 # Snipers outside the guarded ground are ignored.
	if priority != -1:
		target_id = priority
		if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
			state = State.CHASE
			investigate_time = 0.0
			_note_target_acquired()
		return 0.0
	var best := -1
	var best_distance := INF
	var best_score := 0.0
	var nearest_eligible_distance := INF
	for peer_id in players:
		var info: Dictionary = players[peer_id]
		if not info["alive"] or info["safe"]:
			continue
		var p: Vector3 = info["position"]
		if not p.is_finite():
			continue
		var distance := here.distance_to(Vector2(p.x, p.z))
		nearest_eligible_distance = minf(nearest_eligible_distance, distance)
		if behavior == "territorial" and not _in_territory(Vector2(p.x, p.z)):
			continue
		# Night makes infected more vigilant; cap new detection by pursuit leash.
		# Hearing remains independent of night and is always authoritative.
		var sight_multiplier := clampf(float(info.get("notice_multiplier", 1.0)), 1.0, 1.35)
		# Camouflage applies to sight only; noise and blood scent keep their
		# original independent detection ranges and active targets stay locked.
		var visual_raw: float = float(info.get("visual_signature", 1.0))
		var visual: float = 1.0 if not is_finite(visual_raw) else clampf(visual_raw, 0.35, 1.0)
		# Rain impairs only first sight acquisition. The authoritative
		# weather factor cannot exceed ordinary vision or create invisibility.
		var weather_raw: float = float(info.get("weather_sight", 1.0))
		var weather_cover: float = 1.0
		if is_finite(weather_raw):
			weather_cover = clampf(weather_raw, Weather.STORM_SIGHT_MULTIPLIER, 1.0)
		var notice := minf(float(data["notice"]) * sight_multiplier * visual * weather_cover,
			float(data["lose"]) - 1.0)
		# Server-provided wind shifts only first passive sound acquisition.
		# Damage threat, taunts, sight and blood scent retain their own rules.
		var local_wind: Variant = info.get("wind", Vector2.ZERO)
		var wind: Vector2 = local_wind if local_wind is Vector2 else Vector2.ZERO
		var hearing: float = WindHearing.radius(float(info.get("noise", 0.0)),
			wind, Vector2(p.x, p.z), here, float(data["lose"]) - 1.0)
		# Scent can improve discovery but never expands the pursuit leash,
		# overrides combat threat or bypasses safe/dead player protections.
		var scent_raw: float = float(info.get("scent", 0.0))
		var scent: float = 0.0
		if is_finite(scent_raw):
			scent = clampf(scent_raw, 0.0, float(data["lose"]) - 1.0)
		# Firelight reveals campers independently of camouflage, but not beyond
		# this infected type's pursuit leash or the server's safe-zone rules.
		# Like ordinary sight, its first acquisition needs unobstructed cover.
		var firelight_raw: float = float(info.get("firelight", 0.0))
		var firelight: float = 0.0
		if is_finite(firelight_raw):
			firelight = clampf(firelight_raw, 0.0, float(data["lose"]) - 1.0)
		# Quiet sound no longer crosses a solid barricade at its full range.
		# Only marginal sound candidates need one existing world-blocker ray.
		# Loud gunshots penetrate farther; combat threat, scent, sight and
		# existing aggro keep their independent authoritative priorities.
		var heard: bool = false
		if distance <= hearing and distance > scent and peer_id != target_id:
			heard = InfectedHearing.audible(
				world, p, position, float(info.get("noise", 0.0)), hearing)
			if heard and ClassDB.class_exists("AIHearingSensor2D"):
				if _native_senses == null:
					_native_senses = NativeSenses.new()
				# Recording cannot override cover, wind, safe zone, or combat
				# rules: all of them have already passed their normal checks.
				_native_senses.record_confirmed_sound(here, Vector2(p.x, p.z), hearing, int(peer_id))
		var nonvisual: bool = heard or distance <= scent
		var potentially_visible: bool = distance <= maxf(notice, firelight)
		# Utility AI prey choice: proximity dominates; wounds, current focus and noise tip it.
		var utility: float = InfectedTargetUtility.score(distance, float(data["lose"]),
			float(info.get("health_fraction", 1.0)), peer_id == target_id, float(info.get("noise", 0.0)) > 0.0)
		if utility > best_score and (peer_id == target_id or nonvisual or
				(potentially_visible and InfectedSight.clear_path(world, position, p))):
			best = peer_id
			best_score = utility
			best_distance = distance
	if best != -1:
		target_id = best
		if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
			state = State.CHASE
			investigate_time = 0.0
			_note_target_acquired()

	return nearest_eligible_distance

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
	if behavior == "territorial" and not _in_territory(target):
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


const FLANK_FROM := 3.5 # Closer than this, an infected goes straight for its target.
const FLANK_RANGE := 14.0
const FLANK_RING := 2.4
const FLANK_REPLAN_SECONDS := 0.30
const FLANK_INCREMENTAL_STEP := 3 # Bootstrap cap for older native engines.
const FLANK_EQS_TIME_BUDGET_US := 120 # Soft per-granted-query CPU time budget.
const FLANK_EQS_MAX_CANDIDATES := 8 # Hard source-item safety cap for each step.
var _flank_query: Resource
var _flank_goal_cached := Vector2.ZERO
var _flank_here_cached := Vector2.INF
var _flank_target_cached := Vector2.INF
var _flank_replan_remaining := 0.0
var _flank_target_id_cached: int = -1
var _flank_slot_id_cached: int = 0 # Validate cached goal against current server lease.
var flank_reservations: Variant = null # Shared server-owned smart-object lease pool.
var flank_replan_allowed: bool = true # Only optional EQS geometry; combat remains unthrottled.
var flank_incremental_enabled: bool = false # GameServer opts in for 64+ active infected.
var flank_tick_budget: Variant = null # Optional shared, native per-tick EQS ledger.
var flank_step_urgent: bool = false # Lease recovery uses a separate capped pool.
var flank_last_step_us: int = 0 # Measured native score work in this AI tick.
var flank_last_step_candidates: int = 0
var flank_last_timed_steps: int = 0
var _flank_incremental_running: bool = false
var _flank_incremental_target_id: int = -1
var _flank_incremental_here := Vector2.INF
var _flank_incremental_target := Vector2.INF


## Where a chasing infected heads: a pack surrounds its prey instead of queueing behind one another. The engine's
## EnvironmentQuery3D lays a ring of points around the target and ranks them by how close they are to this infected;
## each one takes a different point among the best by its id, so the pack spreads to the sides. Bosses and brutes
## charge straight in, and so does everyone in the last few metres.
func _flank_goal(here: Vector2, target: Vector2) -> Vector2:
	# These per-step counters are set only by a completed native timed call.
	# Direct test calls and unchanged movement never report phantom CPU work.
	flank_last_step_us = 0
	flank_last_step_candidates = 0
	flank_last_timed_steps = 0
	var distance := here.distance_to(target)
	if raid_boss or type == "brute" or distance < FLANK_FROM or distance > FLANK_RANGE \
			or not ClassDB.class_exists("EnvironmentQuery3D"):
		if _flank_incremental_running:
			_flank_query.call("cancel_incremental_top_positions")
			_flank_incremental_running = false
		return target
	# Tactical decisions cost more than movement; cache only while valid.
	# Invalidate cached ring claims when the authoritative target changes.
	if not _flank_incremental_running and _flank_replan_remaining > 0.0 and _flank_target_id_cached == target_id and \
			here.distance_squared_to(_flank_here_cached) <= 3.24 and \
			target.distance_squared_to(_flank_target_cached) <= 1.0:
		# One native/portable O(1) heartbeat validates the exact server-owned
		# claim, keeps its lease alive and atomically marks occupancy as the
		# infected actually reaches (or leaves) the physical flank spot.
		# A preempted/expired handle fails and forces fresh EQS planning.
		if flank_reservations != null and _flank_slot_id_cached > 0 \
				and flank_reservations.has_method("refresh_claim"):
			var at_slot: bool = here.distance_squared_to(_flank_goal_cached) <= 1.0
			if flank_reservations.refresh_claim(_flank_slot_id_cached, id, 1.5, at_slot):
				return _flank_goal_cached
		# Older native engines retain their owner-only query, never a client
		# claim; a portable pool also exposes the new heartbeat above.
		elif flank_reservations == null or not flank_reservations.has_method("get_actor_slot") \
				or int(flank_reservations.get_actor_slot(id)) == _flank_slot_id_cached:
			return _flank_goal_cached
	# Pending query results are tied to the original actor/target context.
	# Discard when combat target changes or geometry becomes too stale.
	if _flank_incremental_running and (not flank_incremental_enabled or \
			_flank_incremental_target_id != target_id or \
			here.distance_squared_to(_flank_incremental_here) > 196.0 or \
			target.distance_squared_to(_flank_incremental_target) > 81.0):
		_flank_query.call("cancel_incremental_top_positions")
		_flank_incremental_running = false
	# Server admission gates ONLY a costly fresh EQS lookup. Valid cached
	# goals are handled above; stale/lost claims take the safe direct-chase
	# path instead of reusing a slot owned by someone else.
	if not flank_replan_allowed:
		return target
	if _flank_query == null:
		_flank_query = ClassDB.instantiate("EnvironmentQuery3D")
		_flank_query.set("horizontal_only", true)
	var use_smart_slots: bool = flank_reservations != null and target_id > 0 and target_id < (1 << 40)
	var incremental_available: bool = flank_incremental_enabled and \
		_flank_query.has_method("begin_incremental_top_positions") and \
		_flank_query.has_method("step_incremental_top_positions") and \
		_flank_query.has_method("get_incremental_random_best_positions")
	# Keep the complete eight-item score band so the final seeded selection
	# is identical to Random Best 25% without a second full scoring pass.
	_flank_query.set("max_results", 8 if use_smart_slots or incremental_available else 3)
	_flank_query.set("origin", Vector3(here.x, 0.0, here.y))
	# UE-style directional EQS context: select the sides or far side of
	# the target instead of wasting a flank slot on its near-side approach.
	# Older engine binaries keep the original ranked-ring behavior.
	if _flank_query.has_method("set_direction_axis"):
		_flank_query.set("direction_origin", Vector3(target.x, 0.0, target.y))
		_flank_query.set("direction_axis", Vector3(target.x - here.x, 0.0, target.y - here.y))
		_flank_query.set("min_direction_dot", -0.25)
		# Angular EQS band: prefer side slots, not straight through the survivor.
		# Older engine binaries retain the original one-sided cone.
		if _flank_query.has_method("set_max_direction_dot"):
			_flank_query.set("max_direction_dot", 0.75)
		_flank_query.set("use_direction", true)
	# Every agent targeting the same survivor now sees the SAME eight ring
	# slots. The server leases distinct slots; old builds without a shared pool
	# retain the original per-agent phase-shifted EQS behavior.
	# The class is optional on stock Godot. Resolve its static method only
	# after the ClassDB guard above, so the server script still parses.
	var ring: PackedVector3Array = ClassDB.call("class_call_static", &"EnvironmentQuery3D", &"sample_ring",
		Vector3(target.x, 0.0, target.y), FLANK_RING, 8,
		0.0 if use_smart_slots else float(posmod(id, 8)) * 0.4)
	_flank_query.set("candidates", ring)
	# The authoritative server grants each agent a per-tick EQS work slot.
	# The native cursor starts conservatively, then adapts to measured CPU
	# microseconds with an eight-item hard maximum per granted work tick.
	# Never use partial rankings to claim a gameplay Smart Object.
	var ranked_indices := PackedInt32Array()
	var ranked := PackedVector3Array()
	var top_count: int = 8 if use_smart_slots or incremental_available else 3
	var incremental: bool = incremental_available and \
		_flank_query.has_method("get_incremental_top_indices")
	var preferred := PackedVector3Array()
	if incremental:
		var global_admission: bool = flank_tick_budget != null and \
			_flank_query.has_method("step_incremental_top_positions_timed") and \
			flank_tick_budget.has_method("try_admit_step")
		# Denied tactical work never blocks movement/attack or consumes a
		# partial result; ordinary and urgent budgets are independent.
		if global_admission and not bool(flank_tick_budget.try_admit_step(flank_step_urgent)):
			return target
		var step_time_us: int = FLANK_EQS_TIME_BUDGET_US
		if global_admission:
			step_time_us = mini(step_time_us, int(
				flank_tick_budget.get_remaining_us(flank_step_urgent)))
		if not _flank_incremental_running:
			if not bool(_flank_query.call("begin_incremental_top_positions", top_count)):
				if global_admission:
					flank_tick_budget.cancel_pending_step()
				return target
			_flank_incremental_running = true
			_flank_incremental_target_id = target_id
			_flank_incremental_here = here
			_flank_incremental_target = target
		var done: bool = false
		if _flank_query.has_method("step_incremental_top_positions_timed") and \
				_flank_query.has_method("suggest_incremental_step_size"):
			# Native measured-cost forecasting starts with a conservative
			# 3-item batch and adapts up/down from observed microseconds.
			# Actual wall clock is still checked between every candidate.
			var budget: int = int(_flank_query.call("suggest_incremental_step_size",
				step_time_us, FLANK_EQS_MAX_CANDIDATES))
			budget = clampi(budget, 1, FLANK_EQS_MAX_CANDIDATES)
			done = bool(_flank_query.call("step_incremental_top_positions_timed",
				step_time_us, budget))
			flank_last_step_us = int(_flank_query.call("get_incremental_last_step_us"))
			flank_last_step_candidates = int(_flank_query.call("get_incremental_last_step_candidates"))
			flank_last_timed_steps = 1
			if global_admission:
				# Debit the shared tick ledger before any next infected can start.
				flank_tick_budget.record_step(flank_last_step_us)
		else:
			# Older Cgame builds retain the original strict 3-item
			# deterministic count budget with identical final results.
			done = bool(_flank_query.call("step_incremental_top_positions", FLANK_INCREMENTAL_STEP))
		if not done:
			return target
		ranked_indices = _flank_query.call("get_incremental_top_indices")
		preferred = _flank_query.call("get_incremental_random_best_positions", 25, id)
		_flank_query.call("cancel_incremental_top_positions")
		_flank_incremental_running = false
	else:
		# Small crowds and older engine builds keep the original synchronous
		# path. Recent builds return exact source indices for duplicate items.
		if _flank_query.has_method("query_top_indices"):
			ranked_indices = _flank_query.call("query_top_indices", top_count)
			for ring_index in ranked_indices:
				if ring_index < 0 or ring_index >= ring.size():
					return target
		else:
			ranked = _flank_query.call("query_top_positions", top_count)
	# No additional candidate scoring after the incremental result
	# completes. Legacy paths retain the existing immediate query.
	if not incremental and _flank_query.has_method("query_random_best_positions"):
		preferred = _flank_query.call("query_random_best_positions", 25, id)
	if not use_smart_slots and preferred.size() == 1:
		ranked_indices = PackedInt32Array()
		ranked = preferred
	if ranked_indices.is_empty() and ranked.is_empty():
		return target
	var spot: Vector3 = ring[ranked_indices[posmod(id, ranked_indices.size())]] \
		if not ranked_indices.is_empty() else ranked[posmod(id, ranked.size())]
	var claimed_slot: int = 0
	if use_smart_slots:
		var slot_ids := PackedInt64Array()
		# The ring's eight distinct locations allow a cheap 1-item lookup.
		# Identity-aware ranked indices from newer engines stay intact.
		if preferred.size() == 1:
			for ring_index in ring.size():
				if ring[ring_index].distance_squared_to(preferred[0]) < 0.0001:
					slot_ids.append(target_id * 16 + ring_index + 1)
					break
		if not ranked_indices.is_empty():
			for ring_index in ranked_indices:
				# Each original EQS candidate retains its unique source ID.
				var sid: int = target_id * 16 + ring_index + 1
				if not slot_ids.has(sid):
					slot_ids.append(sid)
		else:
			for candidate in ranked:
				for ring_index in ring.size():
					if ring[ring_index].distance_squared_to(candidate) < 0.0001:
						# Backwards compatibility with older position-only EQS.
						var sid: int = target_id * 16 + ring_index + 1
						if not slot_ids.has(sid):
							slot_ids.append(sid)
						break
		if slot_ids.is_empty():
			return target
		# Elite AI may preempt ordinary pending claims, not occupied slots.
		# Legacy native builds still use the original exclusive reservation API.
		var claimed: int = 0
		if flank_reservations.has_method("try_claim_first_priority"):
			claimed = int(flank_reservations.try_claim_first_priority(
				slot_ids, id, 1.5, 2 if elite else 0))
		else:
			claimed = int(flank_reservations.try_claim_first(slot_ids, id, 1.5))
		if claimed <= 0:
			return target # An overcrowded pack still pursues normally.
		var claimed_index: int = (claimed - target_id * 16 - 1)
		if claimed_index < 0 or claimed_index >= ring.size():
			return target
		spot = ring[claimed_index]
		claimed_slot = claimed
		if flank_reservations.has_method("set_slot_occupied"):
			var active: bool = here.distance_squared_to(Vector2(spot.x, spot.z)) <= 1.0
			flank_reservations.set_slot_occupied(claimed, id, active)
	_flank_slot_id_cached = claimed_slot
	_flank_goal_cached = Vector2(spot.x, spot.z)
	_flank_here_cached = here
	_flank_target_cached = target
	_flank_target_id_cached = target_id
	_flank_replan_remaining = FLANK_REPLAN_SECONDS
	return _flank_goal_cached

## The server supplies bounded, already-sampled nearby-agent repulsion.
## Malformed native output cannot steer an infected across the world.
func set_passive_crowd_separation(value: Vector2) -> void:
	_passive_crowd_separation = value.limit_length(1.0) if value.is_finite() else Vector2.ZERO


## Server-computed ORCA correction (velocity delta / speed) for the flank-pursuit step only.
## Malformed or oversized values are clamped; zero disables it.
func set_chase_crowd_correction(value: Vector2) -> void:
	_chase_crowd_correction = value.limit_length(CHASE_CROWD_CORRECTION_MAX) if value.is_finite() else Vector2.ZERO


func get_chase_crowd_correction() -> Vector2:
	return _chase_crowd_correction


func _move_toward(world, here: Vector2, goal: Vector2, speed: float, delta: float) -> void:
	if snared_seconds > 0.0:
		stuck_time = 0.0 # A trap cannot be mistaken for a wall to damage.
		return
	var direction := goal - here
	if direction.length() < 0.01:
		return
	direction = direction.normalized()
	# Mass-avoidance style separation is deliberately cosmetic to path choice.
	# Never divert pursuit, melee, boss attacks, snares or combat knockback.
	if state == State.WANDER or state == State.INVESTIGATE:
		direction = (direction + _passive_crowd_separation * 0.35).normalized()
	elif _chase_avoidance_active and _chase_crowd_correction != Vector2.ZERO:
		# ORCA (CgameCrowdAvoidance) velocity correction keeps a chasing pack from piling
		# into one file; bounded so the pursuit heading always keeps a forward component.
		var corrected: Vector2 = direction + _chase_crowd_correction
		if corrected.dot(direction) > 0.05:
			direction = corrected.normalized()
	yaw = atan2(direction.x, direction.y)
	var before := position
	# Zombies use the same movement rules as players, so they are stopped by trees, rocks and deep water.
	# Damage-driven gait changes apply in every walking state, not to attacks.
	var effective_speed: float = speed * InfectedWounds.speed_factor(self)
	position = Movement.move(world, position, direction, effective_speed, delta)
	if before.distance_to(position) < effective_speed * delta * 0.3:
		stuck_time += delta
	else:
		stuck_time = 0.0


## Confirmed crowd control gets weaker on repeated successful applications.
## Failed attempts cannot build immunity, refresh timers or cancel acid windups.
func apply_stagger(seconds: float) -> bool:
	if not EffectRules.can_apply(EffectRules.STAGGER, is_alive(), raid_boss):
		return false
	var stacks: int = stagger_resolve_stacks if stagger_resolve_seconds > 0.0 else 0
	var application: Dictionary = InfectedResolve.plan_application(
		seconds, stacks, stagger_seconds, elite)
	if not bool(application["accepted"]):
		return false
	stagger_seconds = float(application["remaining"])
	stagger_resolve_stacks = int(application["stacks"])
	stagger_resolve_seconds = InfectedResolve.RESET_SECONDS
	# An effective stun interrupts an in-flight acid windup.
	spit_pending = false
	spit_seconds = 0.0
	stuck_time = 0.0
	return true


## Physical impulse from a real server-confirmed melee hit. Elites have
## extra mass, bosses are immovable, and trap-rooted infected stay anchored.
## This cannot move a player, and collision is resolved by shared movement.
func apply_knockback(world, attacker_position: Vector3, meters: float) -> float:
	if not is_alive() or raid_boss or snared_seconds > 0.0:
		return 0.0
	if not position.is_finite() or not attacker_position.is_finite() 			or not is_finite(meters) or meters <= 0.0 or meters > 2.5:
		return 0.0
	var away := Vector2(position.x - attacker_position.x,
		position.z - attacker_position.z)
	if away.length_squared() <= 0.0025 or away.length_squared() > 36.0:
		return 0.0
	var before := Vector2(position.x, position.z)
	var distance: float = meters * (0.5 if elite else 1.0)
	position = Movement.sweep_displacement(world, position,
		away.normalized() * distance, 2.5)
	var displacement: float = before.distance_to(Vector2(position.x, position.z))
	if displacement > 0.001:
		stuck_time = 0.0
	return displacement


## Debuff from an actual server-resolved axe hit. Refreshing cannot stack
## magnitude or extend beyond a single duration from this point in time.
func apply_sunder(now: float, seconds: float) -> bool:
	if not EffectRules.can_apply(EffectRules.SUNDER, is_alive(), raid_boss) or not is_finite(now) or now < 0.0 or 			not is_finite(seconds) or seconds <= 0.0 or seconds > SunderMark.DURATION:
		return false
	sunder_until = maxf(sunder_until, now + seconds)
	return true


## Server-only trap application; cannot target a boss or expired/dead zombie.
func apply_snare(seconds: float) -> bool:
	if not EffectRules.can_apply(EffectRules.SNARE, is_alive(), raid_boss) or not is_finite(seconds) or seconds <= 0.0 or seconds > 3.0:
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
	if perched and attacker_id > 0:
		target_id = attacker_id # Hurt up in the tree: drops onto the attacker next tick.
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		state = State.DEAD
		melee_blocked = false
		spit_pending = false
		spit_seconds = 0.0
		stagger_seconds = 0.0
		stagger_resolve_stacks = 0
		stagger_resolve_seconds = 0.0
		sunder_until = 0.0
		threat.clear()
		return true
	# Damage-derived threat must interrupt a distant passive LOD timer.
	# The selector rechecks attacker validity and safe zones next tick.
	if attacker_id > 0:
		think_timer = 0.0
	if state == State.IDLE or state == State.WANDER:
		state = State.CHASE
	return false
