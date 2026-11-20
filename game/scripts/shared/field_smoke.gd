extends RefCounted
## Ephemeral PvE sight cover. Hearing, scent, firelight, PvP and active threat remain unchanged.
const ITEM_ID := "smoke_charge"
const DURATION := 9.0
const RADIUS := 4.5
const MULTIPLIER := 0.52
const MIN_VISUAL := 0.35
const COOLDOWN := 18.0
const MAX_GLOBAL := 48
const USE_NOISE_RADIUS := 4.0
const USE_NOISE_SECONDS := 0.5


static func inside(clouds: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	var here := Vector2(position.x, position.z)
	for cloud in clouds.values():
		if float(cloud["expires"]) <= now:
			continue
		var site := Vector2(float(cloud["x"]), float(cloud["z"]))
		if here.distance_squared_to(site) <= RADIUS * RADIUS:
			return true
	return false


static func signature(base: float, clouds: Dictionary, position: Vector3,
		now: float, noise_seconds: float, alive: bool) -> float:
	if not is_finite(base) or not is_finite(noise_seconds):
		return 1.0
	var visual := clampf(base, MIN_VISUAL, 1.0)
	if not alive or noise_seconds > 0.0 or not inside(clouds, position, now):
		return visual
	return maxf(MIN_VISUAL, visual * MULTIPLIER)


static func visible(clouds: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var result: Array = []
	if not position.is_finite() or not is_finite(now) or not is_finite(radius) or radius < 0.0:
		return result
	var here := Vector2(position.x, position.z)
	for cloud in clouds.values():
		var left: float = float(cloud["expires"]) - now
		if left <= 0.0:
			continue
		var site := Vector2(float(cloud["x"]), float(cloud["z"]))
		if here.distance_squared_to(site) <= radius * radius:
			result.append({"id": int(cloud["id"]), "x": site.x, "z": site.y,
				"y": float(cloud["y"]), "radius": RADIUS, "remaining": left})
	return result
