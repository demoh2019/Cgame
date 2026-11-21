extends RefCounted
## Session-only reinforcements for the existing party boss, not a new boss.
## Only server-confirmed health and server-owned positions may trigger adds.
const Movement = preload("res://scripts/shared/movement.gd")

const FIRST_THRESHOLD := 0.65
const SECOND_THRESHOLD := 0.30
const MAX_PHASE := 2
const MAX_WAVE := 2
const MIN_PLAYER_DISTANCE := 7.0
const MIN_INFECTED_DISTANCE := 3.5
const MIN_BETWEEN_ADDS := 5.0
const RADII := [9.0, 12.0, 15.0]
const ANGLES := 16
const MAX_THREAT_CONTEXTS := 32
const QUERY_MAX_DISTANCE := 64.0


## Rank already walkable, server-vetted sites by distance to the nearest
## alive player. Native Cgame EnvironmentQuery3D uses exactly the same
## score as this deterministic stock-Godot fallback. No client-supplied
## candidate coordinates or RPCs enter this authoritative selection.
static func rank_sites(candidates: Array[Vector2], threats: Array[Vector2],
		center: Vector2, prefer_native: bool = true) -> Array[Vector2]:
	var ranked: Array[Vector2] = []
	if not center.is_finite():
		return ranked
	for point in candidates:
		if point.is_finite() and point.distance_to(center) <= QUERY_MAX_DISTANCE:
			ranked.append(point)
	if ranked.is_empty() or threats.is_empty():
		return ranked
	var valid_threats: Array[Vector2] = []
	for threat in threats:
		if threat.is_finite():
			valid_threats.append(threat)
	if valid_threats.is_empty():
		return ranked

	# Cgame's multi-threat context is a native, capped Environment Query
	# resource. The same ordering is available without the custom module.
	if prefer_native and valid_threats.size() <= MAX_THREAT_CONTEXTS and ClassDB.class_exists("EnvironmentQuery3D"):
		var query: Object = ClassDB.instantiate("EnvironmentQuery3D")
		if query != null and query.has_method("set_threat_positions"):
			var positions := PackedVector3Array()
			for point in ranked:
				positions.append(Vector3(point.x, 0.0, point.y))
			var contexts := PackedVector3Array()
			for threat in valid_threats:
				contexts.append(Vector3(threat.x, 0.0, threat.y))
			query.set("candidates", positions)
			query.set("origin", Vector3(center.x, 0.0, center.y))
			query.set("horizontal_only", true)
			query.set("max_distance", QUERY_MAX_DISTANCE)
			query.set("distance_weight", 0.0)
			query.set("safety_weight", 1.0)
			query.set("use_threat", true)
			query.set("threat_positions", contexts)
			var native_positions: PackedVector3Array = query.call("query_positions")
			var native_result: Array[Vector2] = []
			for point in native_positions:
				native_result.append(Vector2(point.x, point.z))
			if native_result.size() == ranked.size():
				return native_result

	# Stable sort on the same score as the native EQS resource:
	# min(nearest-threat-distance / 64, 1), ties by candidate index.
	var scored: Array[Dictionary] = []
	for index in ranked.size():
		var point: Vector2 = ranked[index]
		var nearest: float = INF
		for threat in valid_threats:
			nearest = minf(nearest, point.distance_to(threat))
		scored.append({"point": point, "index": index,
			"score": minf(1.0, nearest / QUERY_MAX_DISTANCE)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) == float(b["score"]):
			return int(a["index"]) < int(b["index"])
		return float(a["score"]) > float(b["score"]))
	ranked.clear()
	for entry in scored:
		ranked.append(entry["point"])
	return ranked



static func next_phase(hp: float, max_hp: float, completed: int) -> int:
	if not is_finite(hp) or not is_finite(max_hp) or hp <= 0.0 or max_hp <= 0.0:
		return 0
	if completed == 0 and hp / max_hp <= FIRST_THRESHOLD:
		return 1
	if completed == 1 and hp / max_hp <= SECOND_THRESHOLD:
		return 2
	return 0


static func kinds(phase: int) -> Array[String]:
	if phase == 1:
		return ["runner", "runner"]
	if phase == 2:
		return ["brute", "runner"]
	return []


## Bounded deterministic search on walkable terrain, same PvP risk zone.
static func sites(world, players: Dictionary, zombies: Dictionary,
		center: Vector3, phase: int, count: int) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if not center.is_finite() or phase < 1 or phase > MAX_PHASE or count <= 0:
		return found
	var origin := Vector2(center.x, center.z)
	var zone: int = world.zone_at(origin.x, origin.y)
	if zone < 2 or world.is_safe(origin.x, origin.y):
		return found
	# Preserve all authoritative terrain, zone, player distance and
	# existing-infected exclusions *before* native or script ranking.
	var candidates: Array[Vector2] = []
	for radius in RADII:
		for index in ANGLES:
			var angle: float = float((index + phase * 5) % ANGLES) * TAU / ANGLES
			var point: Vector2 = origin + Vector2.from_angle(angle) * radius
			if world.zone_at(point.x, point.y) != zone or world.is_safe(point.x, point.y) \
					or world.is_water(point.x, point.y) or not Movement._is_free(world, point):
				continue
			var clear := true
			for player in players.values():
				if player.survival.alive and player.position.is_finite() \
						and point.distance_to(Vector2(player.position.x, player.position.z)) < MIN_PLAYER_DISTANCE:
					clear = false
					break
			if not clear:
				continue
			for enemy in zombies.values():
				if enemy.is_alive() and point.distance_to(Vector2(enemy.position.x, enemy.position.z)) < MIN_INFECTED_DISTANCE:
					clear = false
					break
			if clear:
				candidates.append(point)

	# A bounded multi-actor context covers every nearby living survivor,
	# rather than testing just one boss target. Sort by distance to origin
	# before applying the cap; dictionary insertion order cannot change
	# which threats participate in the native query.
	var nearby: Array[Dictionary] = []
	for player in players.values():
		if player.survival.alive and player.position.is_finite():
			var point := Vector2(player.position.x, player.position.z)
			if point.distance_to(origin) <= QUERY_MAX_DISTANCE:
				nearby.append({"position": point, "distance": point.distance_to(origin)})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["distance"]) != float(b["distance"]):
			return float(a["distance"]) < float(b["distance"])
		var ap: Vector2 = a["position"]
		var bp: Vector2 = b["position"]
		return ap.x < bp.x if ap.x != bp.x else ap.y < bp.y)
	var threats: Array[Vector2] = []
	for i in mini(nearby.size(), MAX_THREAT_CONTEXTS):
		threats.append(nearby[i]["position"])
	for point in rank_sites(candidates, threats, origin):
		var separated := true
		for other in found:
			if point.distance_to(other) < MIN_BETWEEN_ADDS:
				separated = false
				break
		if not separated:
			continue
		found.append(point)
		if found.size() >= mini(count, MAX_WAVE):
			return found
	return found
