extends RefCounted
## Siege fortification costs and capture difficulty for party-owned outposts.
## Only the authoritative game server can call fortify() with player inventory.
## This uses no asynchronous work: checking, spending and upgrade are one tick.

const MAX_LEVEL := 3
const BUILD_RADIUS := 4.0
const EXTRA_CAPTURE_SECONDS_PER_LEVEL := 10.0
const COSTS := [
	{},
	{"wood_1": 4, "stone_1": 3},
	{"wood_1": 8, "stone_1": 6},
	{"wood_1": 12, "stone_1": 10},
]


static func cost_for_level(level: int) -> Dictionary:
	if level < 1 or level > MAX_LEVEL:
		return {}
	return (COSTS[level] as Dictionary).duplicate()


static func capture_duration(base_duration: float, level: int) -> float:
	return base_duration + float(clampi(level, 0, MAX_LEVEL)) * EXTRA_CAPTURE_SECONDS_PER_LEVEL


## Returns the result without changing state unless everything is valid.
## A contested point cannot be reinforced, even if the previous tick's
## client-visible contested flag has not yet changed.
static func fortify(site: Dictionary, inventory, group_id: int,
		position: Vector3, now: float, contested_now: bool) -> Dictionary:
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if not position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var point := Vector2(float(site["x"]), float(site["z"]))
	if Vector2(position.x, position.z).distance_squared_to(point) > BUILD_RADIUS * BUILD_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if group_id <= 0 or group_id != int(site["owner"]) or now >= float(site["until"]):
		return {"ok": false, "reason": "not_owner"}
	if contested_now or bool(site["contested"]) or int(site["challenger"]) != 0:
		return {"ok": false, "reason": "contested"}
	var level: int = int(site.get("fortification", 0))
	if level >= MAX_LEVEL:
		return {"ok": false, "reason": "max_level"}
	if level < 0:
		return {"ok": false, "reason": "invalid_level"}
	var cost: Dictionary = cost_for_level(level + 1)
	if not inventory.has_all(cost):
		return {"ok": false, "reason": "missing_items"}
	# Inventory.remove is itself all-or-nothing for one item. Retain a
	# complete rollback snapshot in case a future inventory backend changes.
	var snapshot: Dictionary = inventory.to_dict()
	for item_id in cost:
		if not inventory.remove(item_id, int(cost[item_id])):
			inventory.load_dict(snapshot)
			return {"ok": false, "reason": "missing_items"}
	site["fortification"] = level + 1
	return {
		"ok": true, "level": level + 1, "spent": cost,
		"extra_capture_seconds": float(level + 1) * EXTRA_CAPTURE_SECONDS_PER_LEVEL,
	}
