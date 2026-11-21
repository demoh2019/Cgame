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
const MAX_EXCLUSION_CONTEXTS := 128
const QUERY_MAX_DISTANCE := 64.0
const MAX_RAID_HEIGHT_DIFFERENCE := 3.0 # Reject steep shelves above or below raid bosses.


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


## Choose multiple safe locations without clustering. Only pre-vetted server
## positions enter the native query. A deterministic GDScript path makes the
## result identical on stock Godot and older Cgame binaries.
static func spread_sites(candidates: Array[Vector2], threats: Array[Vector2],
		center: Vector2, count: int, min_separation: float,
		prefer_native: bool = true, exclusions: Array[Vector2] = [],
		min_exclusion_distance: float = 0.0, candidate_heights: Array[float] = [],
		center_height: float = 0.0, max_height_difference: float = 0.0) -> Array[Vector2]:
	var selected: Array[Vector2] = []
	if not center.is_finite() or count <= 0 or count > 64 \
			or not is_finite(min_separation) or min_separation < 0.0 \
			or not is_finite(min_exclusion_distance) or min_exclusion_distance < 0.0 \
		or not is_finite(center_height) or not is_finite(max_height_difference) \
		or max_height_difference < 0.0:
		return selected
	# Missing heights may hide an unsafe candidate late in the list.
	if max_height_difference > 0.0 and candidate_heights.size() != candidates.size():
		return selected
	var vetted: Array[Vector2] = []
	var vetted_heights: Array[float] = []
	for i in candidates.size():
		var point: Vector2 = candidates[i]
		if point.is_finite() and point.distance_to(center) <= QUERY_MAX_DISTANCE:
			vetted.append(point)
			vetted_heights.append(candidate_heights[i] if max_height_difference > 0.0 else center_height)
	if vetted.is_empty():
		return selected

	var valid_threats: Array[Vector2] = []
	for threat in threats:
		if threat.is_finite():
			valid_threats.append(threat)
	var valid_exclusions: Array[Vector2] = []
	for blocker in exclusions:
		if blocker.is_finite():
			valid_exclusions.append(blocker)

	# On native binaries we score and choose separated sites in one query,
	# scanning beyond near-duplicate top candidates rather than truncating first.
	if prefer_native and not valid_threats.is_empty() \
			and valid_threats.size() <= MAX_THREAT_CONTEXTS \
			and ClassDB.class_exists("EnvironmentQuery3D"):
		var query: Object = ClassDB.instantiate("EnvironmentQuery3D")
		if query != null and query.has_method("query_spread_positions") \
				and query.has_method("set_threat_positions") \
				and (max_height_difference <= 0.0 or query.has_method("set_max_vertical_difference")) \
				and (valid_exclusions.is_empty() or (
					valid_exclusions.size() <= MAX_EXCLUSION_CONTEXTS
					and query.has_method("set_exclusion_positions"))):
			var positions := PackedVector3Array()
			for i in vetted.size():
				var point: Vector2 = vetted[i]
				positions.append(Vector3(point.x, vetted_heights[i], point.y))
			var contexts := PackedVector3Array()
			for threat in valid_threats:
				contexts.append(Vector3(threat.x, 0.0, threat.y))
			query.set("candidates", positions)
			query.set("origin", Vector3(center.x, center_height, center.y))
			query.set("horizontal_only", true)
			query.set("max_distance", QUERY_MAX_DISTANCE)
			if max_height_difference > 0.0:
				query.set("max_vertical_difference", max_height_difference)
			query.set("distance_weight", 0.0)
			query.set("safety_weight", 1.0)
			query.set("use_threat", true)
			query.set("threat_positions", contexts)
			if not valid_exclusions.is_empty() and min_exclusion_distance > 0.0:
				var occupied := PackedVector3Array()
				for blocker in valid_exclusions:
					occupied.append(Vector3(blocker.x, 0.0, blocker.y))
				query.set("exclusion_positions", occupied)
				query.set("min_exclusion_distance", min_exclusion_distance)
			var native_points: PackedVector3Array = query.call(
				"query_spread_positions", count, min_separation)
			for point in native_points:
				selected.append(Vector2(point.x, point.z))
			return selected

	# Portable path applies the same inclusive vertical and XZ clearance.
	var permitted: Array[Vector2] = []
	for i in vetted.size():
		var point: Vector2 = vetted[i]
		if max_height_difference > 0.0:
			if not is_finite(vetted_heights[i]) or \
					absf(vetted_heights[i] - center_height) > max_height_difference:
				continue
		var unoccupied := true
		if min_exclusion_distance > 0.0:
			for blocker in valid_exclusions:
				if point.distance_to(blocker) < min_exclusion_distance:
					unoccupied = false
					break
		if unoccupied:
			permitted.append(point)
	# Exact stable ranking and >= threshold match the C++ implementation.
	for point in rank_sites(permitted, valid_threats, center, prefer_native):
		var clear := true
		for other in selected:
			if point.distance_to(other) < min_separation:
				clear = false
				break
		if clear:
			selected.append(point)
			if selected.size() >= count:
				break
	return selected



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


## Sample three encounter bands with the native EQS Donut generator when available.
## Preserve the original source ordering (ring, then phase-rotated angle).
## This only generates untrusted *candidate* geometry; sites() validates all
## terrain, nav, water, player and infected occupancy guards independently.
static func candidate_ring_points(center: Vector2, phase: int,
		prefer_native: bool = true) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not center.is_finite() or phase < 1 or phase > MAX_PHASE:
		return points
	var donut := PackedVector3Array()
	if prefer_native and ClassDB.class_exists("EnvironmentQuery3D") \
			and ClassDB.class_has_method("EnvironmentQuery3D", "sample_donut"):
		# Reflection avoids a parse-time dependency on the optional native class.
		donut = ClassDB.class_call_static("EnvironmentQuery3D", "sample_donut",
			Vector3(center.x, 0.0, center.y), float(RADII[0]),
			float(RADII[RADII.size() - 1]), RADII.size(), ANGLES)
	var has_native: bool = donut.size() == RADII.size() * ANGLES
	for ring_index in RADII.size():
		for index in ANGLES:
			var angle_index: int = (index + phase * 5) % ANGLES
			if has_native:
				var sample: Vector3 = donut[ring_index * ANGLES + angle_index]
				points.append(Vector2(sample.x, sample.z))
			else:
				var angle: float = float(angle_index) * TAU / ANGLES
				points.append(center + Vector2.from_angle(angle) * float(RADII[ring_index]))
	return points


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
	var heights: Array[float] = []
	for point in candidate_ring_points(origin, phase):
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
		candidates.append(point)
		heights.append(world.height_at(point.x, point.y))

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
	# Occupied positions are server-owned; every living infected is checked.
	# More than 128 blockers automatically uses the full GDScript fallback.
	var occupied: Array[Vector2] = []
	for enemy in zombies.values():
		if enemy.is_alive() and enemy.position.is_finite():
			occupied.append(Vector2(enemy.position.x, enemy.position.z))
	return spread_sites(candidates, threats, origin, mini(count, MAX_WAVE),
		MIN_BETWEEN_ADDS, true, occupied, MIN_INFECTED_DISTANCE,
		heights, center.y, MAX_RAID_HEIGHT_DIFFERENCE)
