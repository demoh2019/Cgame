extends RefCounted
## Server-authoritative bounded logistics: every captured outpost may receive
## four survival cargo packs, never infinite ownership extensions.
const Inventory = preload("res://scripts/shared/inventory.gd")
const DELIVERY_RADIUS := 4.0
const EXTRA_SECONDS := 45.0
const MAX_EXTRA_SECONDS := 180.0
const COST := {"canned_food": 2, "water_bottle": 2, "wood_1": 4}


static func deliver(site: Dictionary, player, authorized: bool, now: float,
		contested_now: bool) -> Dictionary:
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if not player.survival.alive:
		return {"ok": false, "reason": "dead"}
	if not player.position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var flag := Vector2(float(site.get("x", NAN)), float(site.get("z", NAN)))
	if not flag.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	if Vector2(player.position.x, player.position.z).distance_squared_to(flag) > DELIVERY_RADIUS * DELIVERY_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if not authorized or int(site.get("owner", 0)) <= 0 or now >= float(site.get("until", 0.0)):
		return {"ok": false, "reason": "not_owner"}
	if contested_now:
		return {"ok": false, "reason": "contested"}
	var already: float = float(site.get("provisioned_seconds", 0.0))
	if not is_finite(already) or already < 0.0 or already > MAX_EXTRA_SECONDS:
		return {"ok": false, "reason": "invalid_stock"}
	if already + EXTRA_SECONDS > MAX_EXTRA_SECONDS:
		return {"ok": false, "reason": "fully_supplied"}
	if not player.inventory.has_all(COST):
		return {"ok": false, "reason": "missing_items"}
	var trial := Inventory.new(player.inventory.slots.size())
	trial.load_dict(player.inventory.to_dict())
	for item_id in COST:
		if not trial.remove(str(item_id), int(COST[item_id])):
			return {"ok": false, "reason": "missing_items"}
	player.inventory.load_dict(trial.to_dict())
	site["provisioned_seconds"] = already + EXTRA_SECONDS
	site["until"] = float(site["until"]) + EXTRA_SECONDS
	return {"ok": true, "site": int(site["id"]), "extra_seconds": EXTRA_SECONDS,
		"provisioned_seconds": site["provisioned_seconds"],
		"remaining_deliveries": int((MAX_EXTRA_SECONDS - float(site["provisioned_seconds"])) / EXTRA_SECONDS),
		"spent": COST.duplicate(true)}
