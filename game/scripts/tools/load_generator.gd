extends RefCounted
## Deterministic multiplayer load generator for the authoritative GameServer.
##
## Drives N scripted bots (wanderer, pvp_brawler, pve_hunter, gatherer, trader) through the same
## server API a network gateway uses (add_player / submit_input / cmd_* / tick) and measures:
## per-tick server time percentiles, events per tick, alive players, zombie count, command
## outcomes per reason, and static-memory samples for leak-trend detection.
##
## Method notes (ideas only, no code taken): fixed-step simulated clients with seeded per-bot RNG
## as in common game-server soak harnesses; leak detection by ordinary least-squares slope over
## periodic memory samples. Original implementation, MIT-compatible, no third-party code.
##
## Scenario: {bots, mix: {behaviour: weight}, duration_s, tick_rate, area: "pvp"|"pve"|"safe"|"mixed", seed}

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

const BEHAVIOURS: Array[String] = ["wanderer", "pvp_brawler", "pve_hunter", "gatherer", "trader"]
const DECISION_INTERVAL_S := 0.25
const MEMORY_SAMPLE_INTERVAL_S := 1.0
const FIRST_PEER_ID := 1000

var _server
var _world
var _rng := RandomNumberGenerator.new()
var _bots: Array[Dictionary] = []
var _cmd_ok: Dictionary = {}
var _cmd_fail: Dictionary = {}
var _event_counts: Dictionary = {}


## Named scenario presets. Overrides are merged on top.
static func preset(name: String, overrides: Dictionary = {}) -> Dictionary:
	var scenario: Dictionary = {
		"bots": 16, "duration_s": 10.0, "tick_rate": 20, "seed": 1337, "area": "mixed",
		"mix": {"wanderer": 1.0, "pvp_brawler": 1.0, "pve_hunter": 1.0, "gatherer": 1.0, "trader": 1.0},
	}
	if name == "pvp":
		scenario["area"] = "pvp"
		scenario["mix"] = {"pvp_brawler": 3.0, "wanderer": 1.0}
	elif name == "pve":
		scenario["area"] = "pve"
		scenario["mix"] = {"pve_hunter": 3.0, "gatherer": 1.0, "wanderer": 1.0}
	for key in overrides:
		scenario[key] = overrides[key]
	return scenario


## Finds a spot at the given world-zone class by scanning rings. pvp: zone >= 2, safe: zone 0.
static func find_spot(world, want_pvp: bool, zone_exact: int, angle: float) -> Vector2:
	var radius := 40.0
	while radius < 1400.0:
		var spot := Vector2(cos(angle), sin(angle)) * radius
		var zone: int = world.zone_at(spot.x, spot.y)
		if want_pvp and zone >= 2:
			return spot
		if not want_pvp and zone == zone_exact:
			return spot
		radius += 20.0
	return Vector2(40.0, 0.0)


func run(scenario: Dictionary) -> Dictionary:
	var seed_value: int = int(scenario.get("seed", 1337))
	var tick_rate: int = maxi(1, int(scenario.get("tick_rate", 20)))
	var duration: float = float(scenario.get("duration_s", 10.0))
	var bot_count: int = maxi(0, int(scenario.get("bots", 16)))
	var delta: float = 1.0 / float(tick_rate)
	var ticks: int = maxi(1, int(round(duration * float(tick_rate))))
	_reset(seed_value)
	_world = WorldGen.new(seed_value)
	_server = GameServer.new(_world, seed_value)
	_server.craft_quality_enabled = false
	_spawn_bots(scenario, bot_count, seed_value)

	var tick_us: PackedFloat64Array = PackedFloat64Array()
	tick_us.resize(ticks)
	var events_per_tick: PackedInt32Array = PackedInt32Array()
	events_per_tick.resize(ticks)
	var alive_sum := 0.0
	var alive_min: int = bot_count
	var zombie_sum := 0.0
	var zombie_max := 0
	var mem_samples: Array[Dictionary] = []
	var sample_every: int = maxi(1, int(round(MEMORY_SAMPLE_INTERVAL_S * float(tick_rate))))
	var decide_every: int = maxi(1, int(round(DECISION_INTERVAL_S * float(tick_rate))))
	var wall_start: int = Time.get_ticks_usec()
	mem_samples.append({"t": 0.0, "bytes": OS.get_static_memory_usage()})

	for tick_index in ticks:
		var decide: bool = tick_index % decide_every == 0
		for bot in _bots:
			_drive_bot(bot, tick_index, delta, decide)
		var started: int = Time.get_ticks_usec()
		_server.tick(delta)
		tick_us[tick_index] = float(Time.get_ticks_usec() - started)
		var drained: Array = _server.drain_events()
		events_per_tick[tick_index] = drained.size()
		for event in drained:
			var kind := str(event.get("type", "?"))
			_event_counts[kind] = int(_event_counts.get(kind, 0)) + 1
		var alive := 0
		for bot in _bots:
			var player = _server.players.get(bot["id"])
			if player != null and player.survival.alive:
				alive += 1
		alive_sum += float(alive)
		alive_min = mini(alive_min, alive)
		var zc: int = _server.zombies.size()
		zombie_sum += float(zc)
		zombie_max = maxi(zombie_max, zc)
		if (tick_index + 1) % sample_every == 0:
			mem_samples.append({"t": float(tick_index + 1) * delta, "bytes": OS.get_static_memory_usage()})
	var wall_s: float = float(Time.get_ticks_usec() - wall_start) / 1000000.0

	var tick_ms: PackedFloat64Array = PackedFloat64Array()
	for us in tick_us:
		tick_ms.append(us / 1000.0)
	var sorted_ms: PackedFloat64Array = tick_ms.duplicate()
	sorted_ms.sort()
	var events_total := 0
	for n in events_per_tick:
		events_total += n
	var cmd_ok_total := 0
	for key in _cmd_ok:
		cmd_ok_total += int(_cmd_ok[key])
	var cmd_fail_total := 0
	for key in _cmd_fail:
		cmd_fail_total += int(_cmd_fail[key])

	var behaviour_counts: Dictionary = {}
	for bot in _bots:
		var b: String = bot["behaviour"]
		behaviour_counts[b] = int(behaviour_counts.get(b, 0)) + 1

	return {
		"bots": bot_count, "ticks": ticks, "tick_rate": tick_rate, "duration_s": duration, "seed": seed_value,
		"area": str(scenario.get("area", "mixed")), "behaviours": behaviour_counts,
		"wall_s": wall_s,
		"tick_ms": {
			"p50": _percentile(sorted_ms, 0.50), "p95": _percentile(sorted_ms, 0.95),
			"p99": _percentile(sorted_ms, 0.99), "max": sorted_ms[sorted_ms.size() - 1],
			"mean": _mean(tick_ms),
		},
		"events": {
			"total": events_total, "per_tick_mean": float(events_total) / float(ticks),
			"per_tick_max": _max_int(events_per_tick), "by_type": _event_counts.duplicate(),
		},
		"players_alive": {"mean": alive_sum / float(ticks), "min": alive_min, "final": _alive_count()},
		"zombies": {"mean": zombie_sum / float(ticks), "max": zombie_max, "final": _server.zombies.size()},
		"commands": {
			"ok_total": cmd_ok_total, "fail_total": cmd_fail_total,
			"ok": _cmd_ok.duplicate(), "fail": _cmd_fail.duplicate(),
		},
		"memory": {
			"samples": mem_samples, "slope_bytes_per_s": memory_slope(mem_samples),
			"start_bytes": mem_samples[0]["bytes"], "end_bytes": mem_samples[mem_samples.size() - 1]["bytes"],
		},
	}


## Ordinary least-squares slope (bytes per simulated second) of memory samples; 0 with < 2 samples.
static func memory_slope(samples: Array) -> float:
	var n: int = samples.size()
	if n < 2:
		return 0.0
	var sum_t := 0.0
	var sum_b := 0.0
	for s in samples:
		sum_t += float(s["t"])
		sum_b += float(s["bytes"])
	var mean_t: float = sum_t / float(n)
	var mean_b: float = sum_b / float(n)
	var num := 0.0
	var den := 0.0
	for s in samples:
		var dt: float = float(s["t"]) - mean_t
		num += dt * (float(s["bytes"]) - mean_b)
		den += dt * dt
	return num / den if den > 0.0 else 0.0


func _reset(seed_value: int) -> void:
	_rng.seed = seed_value
	_bots.clear()
	_cmd_ok.clear()
	_cmd_fail.clear()
	_event_counts.clear()


func _alive_count() -> int:
	var alive := 0
	for bot in _bots:
		var player = _server.players.get(bot["id"])
		if player != null and player.survival.alive:
			alive += 1
	return alive


static func _percentile(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return sorted[idx]


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


static func _max_int(values: PackedInt32Array) -> int:
	var best := 0
	for v in values:
		best = maxi(best, v)
	return best


# --- Bots --------------------------------------------------------------------------------------

func _pick_behaviour(mix: Dictionary, roll: float) -> String:
	var total := 0.0
	for key in BEHAVIOURS:
		total += float(mix.get(key, 0.0))
	if total <= 0.0:
		return "wanderer"
	var target: float = roll * total
	var acc := 0.0
	for key in BEHAVIOURS:
		acc += float(mix.get(key, 0.0))
		if target < acc:
			return key
	return "wanderer"


func _spawn_bots(scenario: Dictionary, count: int, seed_value: int) -> void:
	var mix: Dictionary = scenario.get("mix", {"wanderer": 1.0})
	var area: String = str(scenario.get("area", "mixed"))
	# Anchor spots are found once, scanning world.zone_at, then bots cluster around them.
	var pvp_anchor: Vector2 = find_spot(_world, true, 2, 0.6)
	var pve_anchor: Vector2 = find_spot(_world, false, 1, 2.2)
	var safe_anchor: Vector2 = Vector2(14.0, 6.0)
	for i in count:
		var id: int = FIRST_PEER_ID + i
		var behaviour: String = _pick_behaviour(mix, _rng.randf())
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = seed_value * 7919 + i * 104729 + 13
		var anchor: Vector2
		match behaviour:
			"pvp_brawler":
				anchor = pvp_anchor if area != "safe" else safe_anchor
			"pve_hunter":
				anchor = pve_anchor if area != "safe" else safe_anchor
			"gatherer":
				anchor = pve_anchor if area == "pve" else safe_anchor + Vector2(30.0, 20.0)
			"trader":
				anchor = Vector2(9.0, 3.0)
			_:
				anchor = pvp_anchor if area == "pvp" else (pve_anchor if area == "pve" else safe_anchor)
		var jitter := Vector2(bot_rng.randf_range(-12.0, 12.0), bot_rng.randf_range(-12.0, 12.0))
		var spot: Vector2 = anchor + (jitter if behaviour != "trader" else jitter * 0.1)
		var player = _server.add_player(id, "Bot%d" % i)
		player.position = Vector3(spot.x, _world.height_at(spot.x, spot.y), spot.y)
		_bots.append({
			"id": id, "behaviour": behaviour, "rng": bot_rng, "seq": 0,
			"heading": bot_rng.randf() * TAU, "turn_in": 0, "target": -1, "node": -1, "mx": 0.0, "mz": 0.0,
			"sprint": false, "attack_charge": 0.0, "slot": bot_rng.randi() % 8,
		})


func _drive_bot(bot: Dictionary, tick_index: int, delta: float, decide: bool) -> void:
	var player = _server.players.get(bot["id"])
	if player == null or not player.survival.alive:
		return
	if decide:
		_decide(bot, player, tick_index)
	bot["seq"] = int(bot["seq"]) + 1
	_server.submit_input(bot["id"], bot["seq"], bot["mx"], bot["mz"], bot["sprint"], bot["heading"], delta, false)


func _decide(bot: Dictionary, player, tick_index: int) -> void:
	var rng: RandomNumberGenerator = bot["rng"]
	var behaviour: String = bot["behaviour"]
	match behaviour:
		"pvp_brawler":
			_decide_brawler(bot, player, rng)
		"pve_hunter":
			_decide_hunter(bot, player, rng)
		"gatherer":
			_decide_gatherer(bot, player, rng)
		"trader":
			_decide_trader(bot, player, rng, tick_index)
		_:
			_wander(bot, rng)


func _wander(bot: Dictionary, rng: RandomNumberGenerator) -> void:
	bot["turn_in"] = int(bot["turn_in"]) - 1
	if int(bot["turn_in"]) <= 0:
		bot["heading"] = rng.randf() * TAU
		bot["turn_in"] = rng.randi_range(4, 16)
		bot["sprint"] = rng.randf() < 0.2
	bot["mx"] = sin(float(bot["heading"]))
	bot["mz"] = cos(float(bot["heading"]))


func _steer_to(bot: Dictionary, player, tx: float, tz: float, stop_at: float) -> float:
	var dx: float = tx - player.position.x
	var dz: float = tz - player.position.z
	var dist: float = sqrt(dx * dx + dz * dz)
	if dist > 0.001:
		bot["heading"] = atan2(dx, dz)
	if dist > stop_at:
		bot["mx"] = dx / dist
		bot["mz"] = dz / dist
	else:
		bot["mx"] = 0.0
		bot["mz"] = 0.0
	return dist


func _decide_brawler(bot: Dictionary, player, rng: RandomNumberGenerator) -> void:
	var best_id := -1
	var best_d := INF
	for other_id in _server.players:
		if other_id == bot["id"]:
			continue
		var other = _server.players[other_id]
		if not other.survival.alive:
			continue
		var d: float = Vector2(other.position.x - player.position.x, other.position.z - player.position.z).length()
		if d < best_d or (d == best_d and other_id < best_id):
			best_d = d
			best_id = other_id
	if best_id < 0:
		_wander(bot, rng)
		return
	var target = _server.players[best_id]
	var dist: float = _steer_to(bot, player, target.position.x, target.position.z, 1.4)
	bot["sprint"] = dist > 8.0
	if dist < 2.6:
		var dx: float = target.position.x - player.position.x
		var dz: float = target.position.z - player.position.z
		var charge: float = 0.0 if rng.randf() < 0.7 else 0.5
		_cmd("attack", _server.cmd_attack(bot["id"], dx, dz, charge))


func _decide_hunter(bot: Dictionary, player, rng: RandomNumberGenerator) -> void:
	var best_id := -1
	var best_d := INF
	for zid in _server.zombies:
		var z = _server.zombies[zid]
		var d: float = Vector2(z.position.x - player.position.x, z.position.z - player.position.z).length()
		if d < best_d or (d == best_d and zid < best_id):
			best_d = d
			best_id = zid
	if best_id < 0 or best_d > 120.0:
		_wander(bot, rng)
		return
	var zombie = _server.zombies[best_id]
	var dist: float = _steer_to(bot, player, zombie.position.x, zombie.position.z, 1.6)
	bot["sprint"] = false
	if dist < 2.6:
		_cmd("attack", _server.cmd_attack(bot["id"], zombie.position.x - player.position.x, zombie.position.z - player.position.z, 0.0))


func _decide_gatherer(bot: Dictionary, player, rng: RandomNumberGenerator) -> void:
	if not player.action.is_empty():
		bot["mx"] = 0.0
		bot["mz"] = 0.0
		return
	var node: Dictionary = _nearest_node(player)
	if node.is_empty():
		_wander(bot, rng)
		return
	var dist: float = _steer_to(bot, player, float(node["x"]), float(node["z"]), 1.0)
	bot["sprint"] = false
	if dist < 2.4:
		_cmd("gather", _server.cmd_gather(bot["id"], int(node["id"])))


func _nearest_node(player) -> Dictionary:
	var cell: Vector2i = WorldGen.cell_of(player.position.x, player.position.z)
	var best: Dictionary = {}
	var best_d := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var data: Dictionary = _world.chunk(Vector2i(cell.x + dx, cell.y + dz))
			for node in data["nodes"]:
				if _server.depleted.has(node["id"]):
					continue
				var d: float = Vector2(float(node["x"]) - player.position.x, float(node["z"]) - player.position.z).length()
				if d < best_d:
					best_d = d
					best = node
	return best


func _decide_trader(bot: Dictionary, player, rng: RandomNumberGenerator, tick_index: int) -> void:
	_wander(bot, rng)
	bot["sprint"] = false
	var roll: int = int(bot["slot"]) + tick_index
	match roll % 4:
		0:
			_cmd("market_list", _server.cmd_market_list(bot["id"]))
		1:
			_cmd("market_create", _server.cmd_market_create(bot["id"], "wood", 1, 5 + rng.randi_range(0, 5)))
		2:
			_cmd("market_buy", _server.cmd_market_buy(bot["id"], 1 + rng.randi_range(0, 3), 1, tick_index))
		_:
			_cmd("vendor", _server.cmd_vendor(bot["id"], "bandage", 1, rng.randf() < 0.5))


func _cmd(name: String, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_cmd_ok[name] = int(_cmd_ok.get(name, 0)) + 1
	else:
		var key: String = "%s:%s" % [name, str(result.get("reason", "unknown"))]
		_cmd_fail[key] = int(_cmd_fail.get(key, 0)) + 1
