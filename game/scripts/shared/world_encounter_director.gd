extends RefCounted
## Adaptive PvE incident budgeting for the authoritative GameServer.
## Inspired by encounter directors, but deliberately deterministic and bounded.
## No client-supplied values, persistent state, physics queries or extra RNG.

const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")

const LOCAL_RADIUS: float = 75.0
const LOCAL_HARD_CAP: int = 20
const LOCAL_SOFT_CAP: int = 8
const LOCAL_DENSE_CAP: int = 12
const MINIMUM_HEALTH_RATIO: float = 0.0
const MAXIMUM_HEALTH_RATIO: float = 1.0
const MAX_SQUAD: int = 10

# The engine implements a reusable numeric pressure policy. Server-owned
# counts/health still come exclusively from validated GameServer state.
# Old custom binaries and stock Godot execute the same local reference.
static var _native_checked: bool = false
static var _native_budget: Object = null


static func has_native_budget() -> bool:
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("AIEncounterBudget"):
			var policy: Object = ClassDB.instantiate("AIEncounterBudget")
			if policy != null and policy.has_method("configure_limits") and \
					policy.has_method("get_spawn_budget") and policy.has_method("get_respite_seconds"):
				# Keep engine and game parameter defaults synchronized explicitly;
				# a later gameplay tune does not silently desync native and fallback.
				if bool(policy.call("configure_limits",
						WorldIncidents.MAX_ACTIVE_INFECTED, LOCAL_SOFT_CAP,
						LOCAL_DENSE_CAP, LOCAL_HARD_CAP, 7, MAX_SQUAD, 3)):
					_native_budget = policy
	return _native_budget != null


## Counts living enemies in a bounded radius. Early exit avoids scanning the
## rest of the world after the local crowd has saturated the encounter.
static func nearby_infected(zombies: Dictionary, center: Vector3,
		prefer_native: bool = true) -> int:
	if not center.is_finite():
		return LOCAL_HARD_CAP
	# Reusable Unreal-style 3D relevancy broadphase. Keep exact sphere semantics:
	# underground and aboveground infected must not count as neighbors.
	# Small parties pay no native allocation or hash setup cost.
	# Only trusted server entities are indexed; the client supplies no positions.
	if prefer_native and zombies.size() > 12 and ClassDB.class_exists("SpatialPointGrid3D"):
		var native: Object = ClassDB.instantiate("SpatialPointGrid3D")
		if native != null and native.has_method("rebuild") and native.has_method("count_within"):
			var living_positions: Array[Vector3] = []
			for infected in zombies.values():
				if infected == null or not infected.has_method("is_alive") or not infected.is_alive():
					continue
				var candidate: Variant = infected.get("position")
				if candidate is Vector3 and candidate.is_finite():
					living_positions.append(candidate)
			if bool(native.call("rebuild", living_positions)):
				var count: int = int(native.call("count_within", center,
					LOCAL_RADIUS, LOCAL_HARD_CAP))
				if count >= 0:
					return count
	var radius_squared: float = LOCAL_RADIUS * LOCAL_RADIUS
	var found: int = 0
	for infected in zombies.values():
		if infected == null or not infected.has_method("is_alive") or not infected.is_alive():
			continue
		var position: Variant = infected.get("position")
		if typeof(position) != TYPE_VECTOR3 or not position.is_finite():
			continue
		if center.distance_squared_to(position) <= radius_squared:
			found += 1
			if found >= LOCAL_HARD_CAP:
				return LOCAL_HARD_CAP
	return found


## Server-owned budget is the minimum of local pressure, health sensitivity,
## zone difficulty and the global infected cap. Invalid state fails closed.
static func spawn_budget(total_infected: int, nearby: int,
		health_ratio: float, zone: int, prefer_native: bool = true) -> int:
	# Validate before either native or fallback execution: NaN is unsafe for
	# native comparisons and must not produce an unexpected enemy wave.
	if total_infected < 0 or nearby < 0 or not is_finite(health_ratio):
		return 0
	if prefer_native and has_native_budget():
		return int(_native_budget.call("get_spawn_budget",
			total_infected, nearby, health_ratio, zone))
	var headroom: int = WorldIncidents.MAX_ACTIVE_INFECTED - total_infected
	if headroom <= 0 or nearby >= LOCAL_HARD_CAP:
		return 0
	var budget: int = mini(MAX_SQUAD, 7 + clampi(zone, 0, 3))
	if nearby >= LOCAL_DENSE_CAP:
		budget = mini(budget, 2)
	elif nearby >= LOCAL_SOFT_CAP:
		budget = mini(budget, 4)
	var safe_health: float = clampf(health_ratio, MINIMUM_HEALTH_RATIO, MAXIMUM_HEALTH_RATIO)
	if safe_health <= 0.30:
		budget = mini(budget, 2)
	elif safe_health <= 0.55:
		budget = mini(budget, 4)
	return clampi(budget, 0, headroom)


## Keeps encounter identity (howler, elite cache guard, etc.) at the front.
## Does not mutate the upstream roster or call RandomNumberGenerator.
static func bounded_roster(roster: Array, limit: int) -> Array:
	var selected: Array = []
	for i in range(mini(maxi(limit, 0), roster.size())):
		selected.append(roster[i])
	return selected


## Extra recovery when crowds are building or survivors are badly hurt.
## No shorter-than-original cooldowns and no client-side difficulty controls.
static func respite_seconds(base_delay: float, nearby: int,
		health_ratio: float, prefer_native: bool = true) -> float:
	# Invalid clocks or health cannot reach optional native pacing code.
	if not is_finite(base_delay) or base_delay < 0.0 or not is_finite(health_ratio):
		return 0.0
	if prefer_native and has_native_budget():
		return float(_native_budget.call("get_respite_seconds", base_delay, nearby, health_ratio))
	var bonus: float = 0.0
	if nearby >= LOCAL_DENSE_CAP:
		bonus += 45.0
	elif nearby >= LOCAL_SOFT_CAP:
		bonus += 20.0
	if health_ratio <= 0.30:
		bonus += 30.0
	elif health_ratio <= 0.55:
		bonus += 15.0
	return clampf(base_delay + bonus, base_delay, base_delay + 75.0)
