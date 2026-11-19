extends RefCounted
## Siege breaching: attackers spend refined crafting materials to dismantle
## one tier of a rival party's outpost walls. Executed only on world server.
## No attacker-provided party IDs, prices, cooldowns or fortification levels.

const ACCESS_RADIUS := 4.0
const MIN_ATTACKERS := 2
const BREACH_COOLDOWN := 45.0
const COST := {"plank_2": 2, "bar_2": 2}


static func breach(site: Dictionary, inventory, attacker_group: int,
		attacker_position: Vector3, allies_present: int, now: float) -> Dictionary:
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if not attacker_position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var center := Vector2(float(site.get("x", NAN)), float(site.get("z", NAN)))
	if not center.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	if Vector2(attacker_position.x, attacker_position.z).distance_squared_to(center) > ACCESS_RADIUS * ACCESS_RADIUS:
		return {"ok": false, "reason": "too_far"}
	var owner: int = int(site.get("owner", 0))
	if owner == 0 or attacker_group <= 0 or owner == attacker_group or now >= float(site.get("until", 0.0)):
		return {"ok": false, "reason": "not_enemy"}
	if allies_present < MIN_ATTACKERS:
		return {"ok": false, "reason": "requires_party"}
	var level: int = int(site.get("fortification", 0))
	if level <= 0:
		return {"ok": false, "reason": "unfortified"}
	if level > 3:
		return {"ok": false, "reason": "invalid_level"}
	var ready: float = float(site.get("breach_ready_at", 0.0))
	if now < ready:
		return {"ok": false, "reason": "cooldown", "remaining": ready - now}
	if not inventory.has_all(COST):
		return {"ok": false, "reason": "missing_materials"}
	# Exactly one commit point: validate the whole bill, stage inventory,
	# then lower the fortification only if every item can be removed.
	var snapshot: Dictionary = inventory.to_dict()
	for item_id in COST:
		if not inventory.remove(item_id, int(COST[item_id])):
			inventory.load_dict(snapshot)
			return {"ok": false, "reason": "missing_materials"}
	site["fortification"] = level - 1
	site["breach_ready_at"] = now + BREACH_COOLDOWN
	return {
		"ok": true, "level": level - 1, "spent": COST.duplicate(),
		"cooldown": BREACH_COOLDOWN,
	}
