extends RefCounted
## Finite, contested PvP outpost supply caches. Accounts cannot duplicate
## supplies with repeated RPCs, reconnects or an intentionally full backpack.
## Claims and stock live on the server session, not inside client snapshots.

const Inventory = preload("res://scripts/shared/inventory.gd")
const LootRights = preload("res://scripts/shared/loot_rights.gd")

const CACHE_STOCK := 5
const ACCESS_RANGE := 4.0


static func initialize_capture(site: Dictionary) -> void:
	site["supply_epoch"] = int(site.get("supply_epoch", 0)) + 1
	site["supplies_left"] = CACHE_STOCK
	site["supply_claims"] = {}


static func reward(zone: int) -> Dictionary:
	if zone < 2 or zone > 3:
		return {}
	var tier: int = zone + 1
	return {
		"silver": 10 * tier,
		"scrap": 2 * tier,
		"bar_%d" % tier: 1,
		"bandage": 1,
	}


static func claim(site: Dictionary, player, group_id: int, zone: int,
		now: float, contested: bool) -> Dictionary:
	if not player.survival.alive:
		return {"ok": false, "reason": "dead"}
	if not player.position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var center := Vector2(float(site.get("x", NAN)), float(site.get("z", NAN)))
	var here := Vector2(player.position.x, player.position.z)
	if not center.is_finite() or here.distance_squared_to(center) > ACCESS_RANGE * ACCESS_RANGE:
		return {"ok": false, "reason": "too_far"}
	if group_id <= 0 or int(site.get("owner", 0)) != group_id or now >= float(site.get("until", 0.0)):
		return {"ok": false, "reason": "not_owner"}
	if contested:
		return {"ok": false, "reason": "contested"}
	if int(site.get("supplies_left", 0)) <= 0:
		return {"ok": false, "reason": "empty"}
	var token: String = LootRights.token(player)
	var claims: Dictionary = site.get("supply_claims", {})
	if claims.has(token):
		return {"ok": false, "reason": "already_claimed"}
	var items: Dictionary = reward(zone)
	if items.is_empty():
		return {"ok": false, "reason": "invalid_zone"}
	# Validate every transfer on an isolated inventory before consuming stock.
	var trial = Inventory.new(player.inventory.slots.size())
	trial.load_dict(player.inventory.to_dict())
	for id in items:
		if trial.add(str(id), int(items[id])) > 0:
			return {"ok": false, "reason": "no_space"}
	player.inventory.load_dict(trial.to_dict())
	claims[token] = true
	site["supply_claims"] = claims
	site["supplies_left"] = int(site["supplies_left"]) - 1
	return {"ok": true, "site": int(site["id"]), "reward": items,
		"remaining": int(site["supplies_left"])}
