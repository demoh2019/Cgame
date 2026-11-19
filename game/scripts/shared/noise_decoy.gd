extends RefCounted
## Craftable thrown noise lures for stealthy survivor expeditions.
## Server-owned positions, costs and expiry; no fake player aggro or damage.

const ITEM_ID := "noise_decoy"
const THROW_DISTANCE := 8.0
const HEARING_RADIUS := 23.0
const DURATION := 8.0
const COOLDOWN := 3.0
const MAX_ACTIVE := 48
const MAX_PER_OWNER := 2
const MAX_COORD := 20000.0


## Returns a validated landing site. A requested direction is NOT an
## arbitrary client destination; the server derives all world coordinates.
static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite():
		return {}
	if direction.length_squared() < 0.0001:
		return {}
	var heading: Vector2 = direction.normalized()
	var start := Vector2(origin.x, origin.z)
	var target := start + heading * THROW_DISTANCE
	if absf(target.x) > MAX_COORD or absf(target.y) > MAX_COORD:
		return {}
	if world.is_safe(target.x, target.y) or world.is_water(target.x, target.y):
		return {}
	if world.normal_at(target.x, target.y).y < 0.7:
		return {}
	# Sample the physical flight path so a client cannot throw through trees,
	# rock pillars or barricades to distract enemies on the far side.
	for step in range(1, 9):
		var point: Vector2 = start.lerp(target, float(step) / 8.0)
		for blocker in world.blockers_near(point.x, point.y, 0.35):
			if point.distance_to(Vector2(float(blocker["x"]), float(blocker["z"]))) < (
					float(blocker["radius"]) + 0.3):
				return {}
	return {"x": target.x, "y": world.height_at(target.x, target.y), "z": target.y}


static func is_audible(decoy: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	if float(decoy.get("expires", -1.0)) <= now:
		return false
	var offset := Vector2(position.x - float(decoy["x"]),
			position.z - float(decoy["z"]))
	return offset.length_squared() <= HEARING_RADIUS * HEARING_RADIUS


static func visible_state(decoy: Dictionary, now: float) -> Dictionary:
	return {"id": int(decoy["id"]),
		"x": float(decoy["x"]), "y": float(decoy["y"]), "z": float(decoy["z"]),
		"remaining": clampf(float(decoy["expires"]) - now, 0.0, DURATION)}
