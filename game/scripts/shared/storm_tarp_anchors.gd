extends RefCounted
## Owner-paid single-use upgrade to an already placed expedition tarp.
## No extra safe zone, permanent object or additional tent slot.

const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const ITEM_ID := "storm_tarp_anchors"
const BONUS_SECONDS := 180.0


## Only the server determines the nearest live structure, never an RPC ID.
static func nearest(shelters: Dictionary, player, now: float) -> Dictionary:
	if player == null or not player.position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var origin := Vector2(player.position.x, player.position.z)
	var best_id: int = -1
	var best_distance: float = PortableShelter.PACK_RANGE * PortableShelter.PACK_RANGE
	for key in shelters.keys():
		var tarp: Dictionary = shelters[key]
		var expiry: float = float(tarp.get("expires", NAN))
		if not is_finite(expiry) or expiry <= now:
			continue
		var at := Vector2(float(tarp.get("x", NAN)), float(tarp.get("z", NAN)))
		if not at.is_finite():
			continue
		var distance: float = origin.distance_squared_to(at)
		if distance <= best_distance and (best_id < 0 or
				distance < best_distance or int(key) < best_id):
			best_id = int(key)
			best_distance = distance
	if best_id < 0:
		return {"ok": false, "reason": "no_shelter"}
	var chosen: Dictionary = shelters[best_id]
	if not Structures.can_manage(chosen, player.id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if bool(chosen.get("anchored", false)):
		return {"ok": false, "reason": "already_anchored"}
	return {"ok": true, "id": best_id}


static func new_expiry(tarp: Dictionary, now: float) -> float:
	var expiry: float = float(tarp.get("expires", NAN))
	if not is_finite(expiry) or not is_finite(now) or expiry <= now or (
			bool(tarp.get("anchored", false))):
		return expiry
	return expiry + BONUS_SECONDS


## Everyone inside a genuine live upgraded shelter benefits from cover.
static func anchored_covers(shelters: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	var here := Vector2(position.x, position.z)
	for tarp in shelters.values():
		if not bool(tarp.get("anchored", false)):
			continue
		var expiry: float = float(tarp.get("expires", NAN))
		if not is_finite(expiry) or expiry <= now:
			continue
		var at := Vector2(float(tarp.get("x", NAN)), float(tarp.get("z", NAN)))
		if at.is_finite() and here.distance_squared_to(at) <= (
				PortableShelter.COVER_RADIUS * PortableShelter.COVER_RADIUS):
			return true
	return false
