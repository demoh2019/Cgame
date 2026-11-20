extends RefCounted
## One paid, shared storm-resistant fuel upgrade for temporary field fires.
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const ITEM_ID := "stormproof_briquette"
const FUEL_SECONDS := 120.0
const SHIELD_SECONDS := 90.0


## The server chooses a nearby living fire; no arbitrary client IDs.
static func nearest(campfires: Dictionary, position: Vector3, now: float) -> Dictionary:
	if not position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var target_id: int = -1
	var distance: float = FieldCampfire.REFUEL_RANGE * FieldCampfire.REFUEL_RANGE
	var here := Vector2(position.x, position.z)
	for id in campfires.keys():
		var camp: Dictionary = campfires[id]
		if float(camp.get("expires", -1.0)) <= now:
			continue
		var point := Vector2(float(camp.get("x", NAN)), float(camp.get("z", NAN)))
		if not point.is_finite():
			continue
		var d: float = here.distance_squared_to(point)
		if d <= distance and (target_id < 0 or d < distance or int(id) < target_id):
			distance = d
			target_id = int(id)
	if target_id < 0:
		return {"ok": false, "reason": "no_fire"}
	var selected: Dictionary = campfires[target_id]
	if float(selected.get("stormproof_until", 0.0)) > now:
		return {"ok": false, "reason": "already_stormproof"}
	var reason: String = FieldCampfire.refuel_reason(selected, position, now)
	if reason != "":
		return {"ok": false, "reason": reason}
	return {"ok": true, "id": target_id}


## Exact unshielded fraction of a tick. Normal time already elapses once.
## Protection is not retroactive when a tick straddles the shield deadline.
static func exposed_seconds(delta: float, now: float, fire: Dictionary) -> float:
	if not is_finite(delta) or delta <= 0.0 or not is_finite(now):
		return 0.0
	var until: float = float(fire.get("stormproof_until", 0.0))
	if not is_finite(until) or until <= 0.0:
		return delta
	return clampf(now - maxf(now - delta, until), 0.0, delta)
