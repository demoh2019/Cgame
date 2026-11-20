extends RefCounted
## A party guard must actually escort a cargo carrier from its source.
## Only successful, server-resolved movement increments this session ledger.
## Shares come from the original courier payout: never mint bonus silver.
const Inventory = preload("res://scripts/shared/inventory.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")

const START_RADIUS := 50.0
const FOLLOW_RADIUS := 28.0
const ARRIVAL_RADIUS := 20.0
const MIN_ESCORT_METERS := 80.0
const MAX_STEP_METERS := 4.0
const MAX_ESCORT_SHARE := 0.20


static func _route_key(route: Dictionary) -> String:
	if not route.has("src_id") or not route.has("dst_id"):
		return ""
	return "%d:%d" % [int(route["src_id"]), int(route["dst_id"])]


static func _direction(route: Dictionary) -> Dictionary:
	for key in ["src_x", "src_z", "dst_x", "dst_z"]:
		if not route.has(key) or not (route[key] is float or route[key] is int):
			return {}
	var source := Vector2(float(route["src_x"]), float(route["src_z"]))
	var goal := Vector2(float(route["dst_x"]), float(route["dst_z"]))
	var length: float = source.distance_to(goal)
	if not source.is_finite() or not goal.is_finite() or not is_finite(length) or \
			length < CaravanRoutes.MIN_ROUTE_DISTANCE:
		return {}
	return {"source": source, "goal": goal, "length": length,
		"unit": (goal - source) / length}


## Consecutive checkpoints at departure, 30%, 60%, 80%. A guard who
## joins near the delivery point cannot retrospectively claim a trip.
static func record(progress: Dictionary, courier_id: int, escort_id: int,
		group_id: int, route: Dictionary, courier_pos: Vector3,
		escort_pos: Vector3, actual_moved: float) -> void:
	if courier_id <= 0 or escort_id <= 0 or courier_id == escort_id or group_id <= 0 \
			or not courier_pos.is_finite() or not escort_pos.is_finite() or \
			not is_finite(actual_moved) or actual_moved <= 0.0:
		return
	var route_key: String = _route_key(route)
	var geometry: Dictionary = _direction(route)
	if route_key.is_empty() or geometry.is_empty():
		return
	var escort := Vector2(escort_pos.x, escort_pos.z)
	var carrier := Vector2(courier_pos.x, courier_pos.z)
	if escort.distance_to(carrier) > FOLLOW_RADIUS:
		return
	var source: Vector2 = geometry["source"]
	var length: float = float(geometry["length"])
	var entries: Dictionary = progress.get(courier_id, {})
	var state: Dictionary = entries.get(escort_id, {})
	if not state.is_empty() and (int(state.get("group", 0)) != group_id or \
			str(state.get("route", "")) != route_key):
		state = {}
	if state.is_empty():
		if escort.distance_to(source) > START_RADIUS or \
				carrier.distance_to(source) > START_RADIUS:
			return
		state = {"group": group_id, "route": route_key, "stage": 1, "meters": 0.0}
		entries[escort_id] = state
		progress[courier_id] = entries
		return
	state["meters"] = minf(5000.0, float(state["meters"]) +
		minf(actual_moved, MAX_STEP_METERS))
	var forward: float = (escort - source).dot(geometry["unit"])
	match int(state["stage"]):
		1:
			if forward >= length * 0.30:
				state["stage"] = 2
		2:
			if forward >= length * 0.60:
				state["stage"] = 3
		3:
			if forward >= length * 0.80:
				state["stage"] = 4


static func qualifies(progress: Dictionary, courier_id: int, escort_id: int,
		group_id: int, route: Dictionary, courier_pos: Vector3,
		escort_pos: Vector3) -> bool:
	if not courier_pos.is_finite() or not escort_pos.is_finite():
		return false
	var entries: Dictionary = progress.get(courier_id, {})
	var state: Dictionary = entries.get(escort_id, {})
	if state.is_empty() or int(state.get("group", 0)) != group_id or \
			str(state.get("route", "")) != _route_key(route) or \
			int(state.get("stage", 0)) < 4 or \
			float(state.get("meters", 0.0)) < MIN_ESCORT_METERS:
		return false
	var geometry: Dictionary = _direction(route)
	if geometry.is_empty():
		return false
	var escort := Vector2(escort_pos.x, escort_pos.z)
	var carrier := Vector2(courier_pos.x, courier_pos.z)
	return escort.distance_to(carrier) <= FOLLOW_RADIUS and \
		escort.distance_to(geometry["goal"]) <= ARRIVAL_RADIUS


static func status(progress: Dictionary, courier_id: int, escort_id: int,
		group_id: int, route: Dictionary) -> Dictionary:
	var entries: Dictionary = progress.get(courier_id, {})
	var state: Dictionary = entries.get(escort_id, {})
	if state.is_empty() or int(state.get("group", 0)) != group_id or \
			str(state.get("route", "")) != _route_key(route):
		return {}
	return {"stage": int(state["stage"]), "meters": floori(float(state["meters"]))}


static func clear_peer(progress: Dictionary, peer_id: int) -> void:
	progress.erase(peer_id)
	for courier_id in progress.keys():
		var entries: Dictionary = progress[courier_id]
		entries.erase(peer_id)
		if entries.is_empty():
			progress.erase(courier_id)


## Stage all inventory changes before committing any. Escort money is
## subtracted from the original courier payout; total remains unchanged.
static func settle(courier, escorts: Array, route: Dictionary) -> Dictionary:
	if escorts.size() > 4:
		return {"ok": false, "reason": "too_many_escorts"}
	var staged := Inventory.new(courier.inventory.slots.size())
	staged.load_dict(courier.inventory.to_dict())
	var outcome: Dictionary = CaravanRoutes.deliver(staged, route)
	if not bool(outcome.get("ok", false)):
		return outcome
	var payout: int = int(outcome["silver"])
	var each: int = floori(float(payout) * MAX_ESCORT_SHARE /
		float(maxi(1, escorts.size()))) if not escorts.is_empty() else 0
	var total: int = each * escorts.size()
	if total > 0 and not staged.remove("silver", total):
		return {"ok": false, "reason": "transaction_failed"}
	var waiting: Array = []
	var paid: Array = []
	for escort in escorts:
		if escort == null or escort.id == courier.id:
			return {"ok": false, "reason": "invalid_escort"}
		var wallet := Inventory.new(escort.inventory.slots.size())
		wallet.load_dict(escort.inventory.to_dict())
		if wallet.add("silver", each) != 0:
			return {"ok": false, "reason": "escort_no_space"}
		waiting.append({"player": escort, "wallet": wallet})
		paid.append({"peer": escort.id, "silver": each})
	# One commit point; no side effects on any earlier rejection.
	courier.inventory.load_dict(staged.to_dict())
	for entry in waiting:
		entry["player"].inventory.load_dict(entry["wallet"].to_dict())
	outcome["gross_silver"] = payout
	outcome["silver"] = payout - total
	outcome["escorts"] = paid
	return outcome
