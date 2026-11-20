extends RefCounted
## Timed, single-use blast resistance for an authenticated owner's wall.
## No client-provided wall ID, position, shield percentage or timer.
const Structures = preload("res://scripts/shared/structures.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const ITEM_ID := "siege_blast_brace"
const REACH := 3.0
const DURATION := 180.0
const BLOCK_FRACTION := 0.55


static func nearest(world, player, walls: Dictionary, braces: Dictionary,
		charges: Dictionary, now: float) -> Dictionary:
	if player == null or not player.position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var here := Vector2(player.position.x, player.position.z)
	if not ZoneRisk.allows_pvp(world.zone_at(here.x, here.y)):
		return {"ok": false, "reason": "safe_zone"}
	var best: int = -1
	var distance: float = INF
	for id in walls:
		var wall: Dictionary = walls[id]
		var point := Vector2(float(wall.get("x", INF)), float(wall.get("z", INF)))
		if not point.is_finite():
			continue
		var current: float = here.distance_to(point)
		if current <= REACH and (current < distance or
				(is_equal_approx(current, distance) and
				(best == -1 or int(id) < best))):
			best = int(id)
			distance = current
	if best < 0:
		return {"ok": false, "reason": "no_barricade"}
	var selected: Dictionary = walls[best]
	if not Structures.can_manage(selected, player.id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if not ZoneRisk.allows_pvp(world.zone_at(float(selected["x"]),
			float(selected["z"]))):
		return {"ok": false, "reason": "safe_zone"}
	if float(selected.get("hp", 0.0)) <= 0.0:
		return {"ok": false, "reason": "broken"}
	if active(braces, best, now):
		return {"ok": false, "reason": "already_braced"}
	for device in charges.values():
		if int(device.get("wall", -1)) == best:
			return {"ok": false, "reason": "under_siege"}
	return {"ok": true, "wall": best,
		"x": float(selected["x"]), "z": float(selected["z"])}


static func active(braces: Dictionary, id: int, now: float) -> bool:
	return is_finite(now) and braces.has(id) and float(braces[id]) > now


static func absorb(braces: Dictionary, id: int, damage: float,
		now: float) -> Dictionary:
	if not is_finite(damage) or damage <= 0.0:
		return {"damage": damage, "absorbed": 0.0}
	if not active(braces, id, now):
		braces.erase(id)
		return {"damage": damage, "absorbed": 0.0}
	braces.erase(id) # Exactly one physical siege explosion.
	var protected: float = damage * BLOCK_FRACTION
	return {"damage": damage - protected, "absorbed": protected}


static func sweep(braces: Dictionary, walls: Dictionary, now: float) -> void:
	for id in braces.keys():
		if not walls.has(id) or not active(braces, int(id), now):
			braces.erase(id)
