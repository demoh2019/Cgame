extends RefCounted
## Session-only shoreline nets: the server picks water, time and catch tier.
const Fishing = preload("res://scripts/shared/fishing.gd")
const ITEM_ID := "shore_fish_trap"
const CATCH_SECONDS := 120.0
const LIFETIME_SECONDS := 600.0
const COUNT := 2
const COLLECT_RANGE := 4.5
const MIN_SEPARATION := 4.0
const MAX_GLOBAL := 80


static func site(world, position: Vector3, traps: Dictionary, now: float) -> Dictionary:
	if not position.is_finite() or not is_finite(now) or now < 0.0:
		return {"ok": false, "reason": "invalid_position"}
	if world.is_safe(position.x, position.z):
		return {"ok": false, "reason": "safe_zone"}
	var water: Vector2 = Fishing.water_near(world, position)
	if not water.is_finite():
		return {"ok": false, "reason": "need_water"}
	for trap in traps.values():
		var site_point := Vector2(float(trap["x"]), float(trap["z"]))
		if float(trap["expires"]) > now and water.distance_squared_to(site_point) < MIN_SEPARATION * MIN_SEPARATION:
			return {"ok": false, "reason": "blocked"}
	return {"ok": true, "x": water.x, "z": water.y}


static func collectable(position: Vector3, trap: Dictionary) -> bool:
	if not position.is_finite() or trap.is_empty():
		return false
	return Vector2(position.x, position.z).distance_squared_to(
		Vector2(float(trap["x"]), float(trap["z"]))) <= COLLECT_RANGE * COLLECT_RANGE


static func visible(traps: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var result: Array = []
	if not position.is_finite() or not is_finite(now) or not is_finite(radius) or radius < 0.0:
		return result
	var at := Vector2(position.x, position.z)
	for trap in traps.values():
		var remaining: float = float(trap["expires"]) - now
		if remaining <= 0.0:
			continue
		var spot := Vector2(float(trap["x"]), float(trap["z"]))
		if at.distance_squared_to(spot) <= radius * radius:
			result.append({"id": int(trap["id"]), "x": spot.x, "z": spot.y,
				"y": float(trap["y"]), "tier": int(trap["tier"]),
				"ready": now >= float(trap["ready_at"]),
				"ready_in": maxf(0.0, float(trap["ready_at"]) - now),
				"remaining": remaining})
	return result
