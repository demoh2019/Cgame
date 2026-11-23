extends RefCounted
## Ephemeral PvE sight cover. Hearing, scent, firelight, PvP and active threat remain unchanged.
const Weather = preload("res://scripts/shared/weather.gd")
const ITEM_ID := "smoke_charge"
const DURATION := 9.0
const RADIUS := 4.5
const HEIGHT_LIMIT := 3.0 # Smoke on a lower floor cannot conceal an upstairs player.
const MULTIPLIER := 0.52
const MIN_VISUAL := 0.35
const COOLDOWN := 18.0
const MAX_GLOBAL := 48
const USE_NOISE_RADIUS := 4.0
const USE_NOISE_SECONDS := 0.5


## Advances a paid smoke volume by one authoritative simulation tick. The
## centre drifts; sight protection follows the volume, not its cast location.
## Water, sanctuary borders and invalid time stop the cloud rather than
## letting it cross into safe hubs or disappear for a free re-cast.
static func drift(cloud: Dictionary, world, now: float, delta: float) -> Dictionary:
	var updated: Dictionary = cloud.duplicate(true)
	if cloud.is_empty() or not is_finite(now) or not is_finite(delta) or \
			delta <= 0.0 or delta > DURATION:
		return updated
	var expiry: float = float(cloud.get("expires", 0.0))
	var here := Vector2(float(cloud.get("x", NAN)), float(cloud.get("z", NAN)))
	if not is_finite(expiry) or expiry <= now or not here.is_finite():
		return updated
	var wind: Vector2 = Weather.wind_at(world, here.x, here.y, now)
	var next: Vector2 = here + wind * delta
	if not next.is_finite() or world.is_water(next.x, next.y) or \
			world.is_safe(next.x, next.y):
		return updated
	updated["x"] = next.x
	updated["z"] = next.y
	var ground_height: float = world.height_at(next.x, next.y)
	if not is_finite(ground_height):
		return cloud.duplicate(true)
	updated["y"] = ground_height
	return updated


## Only finite, live, fully specified server smoke is allowed to conceal.
static func _live_volume(value: Variant, now: float) -> bool:
	if not (value is Dictionary):
		return false
	var cloud: Dictionary = value
	var expiry: float = float(cloud.get("expires", NAN))
	if not is_finite(expiry) or expiry <= now:
		return false
	var x: float = float(cloud.get("x", NAN))
	var y: float = float(cloud.get("y", NAN))
	var z: float = float(cloud.get("z", NAN))
	return is_finite(x) and is_finite(y) and is_finite(z)


static func inside(clouds: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	var here := Vector2(position.x, position.z)
	for value in clouds.values():
		if not _live_volume(value, now):
			continue
		var cloud: Dictionary = value
		if absf(position.y - float(cloud["y"])) > HEIGHT_LIMIT:
			continue
		var site := Vector2(float(cloud["x"]), float(cloud["z"]))
		if here.distance_squared_to(site) <= RADIUS * RADIUS:
			return true
	return false

static func signature(base: float, clouds: Dictionary, position: Vector3,
		now: float, noise_seconds: float, alive: bool) -> float:
	if not is_finite(base) or not is_finite(noise_seconds) or noise_seconds < 0.0:
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
	for value in clouds.values():
		if not _live_volume(value, now):
			continue
		var cloud: Dictionary = value
		if not cloud.has("id") or absf(position.y - float(cloud["y"])) > HEIGHT_LIMIT:
			continue
		var site := Vector2(float(cloud["x"]), float(cloud["z"]))
		if here.distance_squared_to(site) <= radius * radius:
			result.append({"id": int(cloud["id"]), "x": site.x, "z": site.y,
				"y": float(cloud["y"]), "radius": RADIUS,
				"remaining": float(cloud["expires"]) - now})
	return result
