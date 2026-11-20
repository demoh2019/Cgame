extends RefCounted
## Server-authoritative PvE fire field from a paid thrown consumable.
const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")

const ITEM_ID := "ember_flask"
const RADIUS := 3.0
const DURATION := 6.0
const TICK_SECONDS := 1.0
const DAMAGE_PER_TICK := 8.0
const MAX_TARGETS_PER_TICK := 4
const MAX_ACTIVE := 16
const MAX_PER_OWNER := 2
const COOLDOWN_SECONDS := 12.0
const NOISE_RADIUS := 19.0
const NOISE_SECONDS := 1.5
const MAX_HEIGHT := 2.5


static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary:
	return NoiseDecoy.landing(world, origin, direction)


static func make_pool(id: int, site: Dictionary, owner: int, now: float) -> Dictionary:
	if id <= 0 or owner <= 0 or not is_finite(now):
		return {}
	for component in ["x", "y", "z"]:
		if not site.has(component) or not is_finite(float(site[component])):
			return {}
	return {"id": id, "owner": owner,
		"x": float(site["x"]), "y": float(site["y"]), "z": float(site["z"]),
		"expires": now + DURATION, "next_tick": now + TICK_SECONDS}


static func remaining(pool: Dictionary, now: float) -> float:
	if pool.is_empty() or not is_finite(now):
		return 0.0
	var expires: float = float(pool.get("expires", NAN))
	return clampf(expires - now, 0.0, DURATION) if is_finite(expires) else 0.0


static func public_state(pool: Dictionary, now: float) -> Dictionary:
	return {"id": int(pool["id"]), "x": float(pool["x"]),
		"y": float(pool["y"]), "z": float(pool["z"]),
		"radius": RADIUS, "remaining": remaining(pool, now)}


## Cover, height, safe zones and radius are checked for every damage tick.
static func affects(world, center: Vector2, target: Vector3) -> bool:
	if not center.is_finite() or not target.is_finite() or 			not is_finite(center.distance_squared_to(Vector2(target.x, target.z))):
		return false
	if world.is_safe(target.x, target.z):
		return false
	if absf(target.y - world.height_at(center.x, center.y)) > MAX_HEIGHT:
		return false
	var offset := Vector2(target.x, target.z) - center
	var distance: float = offset.length()
	if distance > RADIUS:
		return false
	if distance > 0.1 and RangedCover.first_blocker_distance(
			world, center, offset, distance) < distance - 0.05:
		return false
	return true
