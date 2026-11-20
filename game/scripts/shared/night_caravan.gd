extends RefCounted
## A real, night-time delivery premium for trade routes. Only confirmed server
## movement with all cargo advances the journal; no client supplied waypoints,
## distance, time, zone, route IDs, silver amounts or progress are accepted.
##
## Progress never goes backwards. Only NEW forward progress counts toward the
## night quota, so walking circles, reversing and waiting cannot farm credit.

const NIGHT_BONUS_RATE := 0.20
const MAX_BONUS_SILVER := 28
const MIN_NIGHT_METERS := 80.0
const MAX_REQUIRED_METERS := 160.0
const MAX_STEP_METERS := 4.0
const MIN_DANGER_ZONE := 1


static func initial(route: Dictionary) -> Dictionary:
	if route.is_empty():
		return {}
	return {"src_id": int(route.get("src_id", -1)),
		"dst_id": int(route.get("dst_id", -1)),
		"forward": 0.0, "night_meters": 0.0}


static func _geometry(route: Dictionary) -> Dictionary:
	for key in ["src_id", "dst_id", "src_x", "src_z", "dst_x", "dst_z",
			"distance", "quantity", "cargo", "silver"]:
		if not route.has(key):
			return {}
	var source := Vector2(float(route["src_x"]), float(route["src_z"]))
	var target := Vector2(float(route["dst_x"]), float(route["dst_z"]))
	var length: float = float(route["distance"])
	if not source.is_finite() or not target.is_finite() or not is_finite(length) \
			or length < 190.0 or length > 900.0 or \
			source.distance_to(target) < 189.0 or \
			int(route["quantity"]) < 1:
		return {}
	return {"source": source, "unit": (target - source).normalized(), "length": length}


static func valid_state(value: Variant, route: Dictionary) -> bool:
	if not (value is Dictionary):
		return false
	var state: Dictionary = value
	if state.is_empty():
		return true # Legacy characters have no night journal.
	if route.is_empty() or state.size() != 4 or _geometry(route).is_empty():
		return false
	for field in ["src_id", "dst_id"]:
		if not state.has(field) or not (state[field] is int) \
				or int(state[field]) != int(route[field]):
			return false
	for field in ["forward", "night_meters"]:
		if not state.has(field) or not (state[field] is float or state[field] is int) \
				or not is_finite(float(state[field])):
			return false
	var forward: float = float(state["forward"])
	var night: float = float(state["night_meters"])
	return forward >= 0.0 and forward <= float(route["distance"]) and \
		night >= 0.0 and night <= forward


## All positions are the result of the server's Movement.step, after collision.
## Progress on a route is counted once at its farthest forward projection.
## 'night' and 'zone' are read from the server world, never from network data.
static func record(state: Dictionary, route: Dictionary, before: Vector3,
		after: Vector3, night: bool, zone: int, cargo_count: int,
		safe: bool = false) -> bool:
	if not valid_state(state, route) or state.is_empty() or \
			not before.is_finite() or not after.is_finite() or \
			cargo_count < int(route["quantity"]):
		return false
	var geometry: Dictionary = _geometry(route)
	if geometry.is_empty():
		return false
	var from := Vector2(before.x, before.z)
	var to := Vector2(after.x, after.z)
	var moved: float = from.distance_to(to)
	if not is_finite(moved) or moved <= 0.0:
		return false
	var origin: Vector2 = geometry["source"]
	var unit: Vector2 = geometry["unit"]
	var length: float = float(geometry["length"])
	var previous: float = float(state["forward"])
	var from_forward: float = clampf((from - origin).dot(unit), 0.0, length)
	var to_forward: float = clampf((to - origin).dot(unit), 0.0, length)
	if to_forward <= previous:
		return false
	# Counting the overlap with the previous max prevents teleport/replay and
	# catches only actual forward movement; one input cannot credit > 4 metres.
	var gained: float = minf(MAX_STEP_METERS,
		maxf(0.0, to_forward - maxf(previous, from_forward)))
	state["forward"] = to_forward
	if night and not safe and zone >= MIN_DANGER_ZONE and zone <= 3 and gained > 0.0:
		state["night_meters"] = minf(length, float(state["night_meters"]) + gained)
	return true


static func required_meters(route: Dictionary) -> float:
	if _geometry(route).is_empty():
		return 0.0
	return maxf(MIN_NIGHT_METERS,
		minf(MAX_REQUIRED_METERS, float(route["distance"]) * 0.25))


static func earned_bonus(route: Dictionary, state: Dictionary) -> int:
	if state.is_empty() or not valid_state(state, route):
		return 0
	var minimum: float = required_meters(route)
	if minimum <= 0.0 or float(state["night_meters"]) + 0.0001 < minimum:
		return 0
	var payout: int = int(route["silver"])
	if payout < 50 or payout > 140:
		return 0
	return mini(MAX_BONUS_SILVER, roundi(float(payout) * NIGHT_BONUS_RATE))


static func public_state(route: Dictionary, state: Dictionary) -> Dictionary:
	if route.is_empty() or not valid_state(state, route):
		return {}
	var minimum: float = required_meters(route)
	if minimum <= 0.0:
		return {}
	return {"night_meters": floori(float(state.get("night_meters", 0.0))),
		"required_meters": ceili(minimum),
		"qualified": earned_bonus(route, state) > 0,
		"bonus_silver": earned_bonus(route, state),
		"potential_bonus": mini(MAX_BONUS_SILVER,
			roundi(float(route["silver"]) * NIGHT_BONUS_RATE))}
