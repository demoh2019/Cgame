extends RefCounted
## A special infected arcing attack. Server chooses the landing point and
## impact moment; the client merely renders the warning ground circle.

const MIN_ZONE := 2 # Red and black PvP/resource tiers only.
const RANGE := 12.0
const MIN_RANGE := 3.0
const RADIUS := 2.4
const WINDUP_SECONDS := 1.4
const COOLDOWN := 6.0
const INFECTION_PER_HIT := 10.0
# After the initial warned splash, corrosive ground remains dangerous.
# Cap active pools and globally limit overlapping pools to one hit per
# survivor per second, so multiple spitters cannot instantly kill someone.
const POOL_SECONDS := 5.0
const POOL_DAMAGE := 3.0
const POOL_INFECTION := 1.0
const POOL_TICK_SECONDS := 1.0
const MAX_ACTIVE_POOLS := 64
# Temporary acid puddles can corrode walls during sieges. The existing
# tier-dependent structure damage factor is applied by the server.
const STRUCTURE_CORROSION_DAMAGE := 8.0


static func corrodes_wall(center: Vector2, wall_position: Vector2, wall_radius: float) -> bool:
	if not center.is_finite() or not wall_position.is_finite() 			or not is_finite(wall_radius) or wall_radius <= 0.0:
		return false
	var radius: float = RADIUS + wall_radius
	return center.distance_squared_to(wall_position) <= radius * radius


static func make_pool(id: int, center: Vector2, ground_y: float,
		now: float, source_id: int) -> Dictionary:
	if id <= 0 or source_id <= 0 or not center.is_finite() 			or not is_finite(ground_y) or not is_finite(now):
		return {}
	return {"id": id, "x": center.x, "y": ground_y, "z": center.y,
		"source": source_id, "expires": now + POOL_SECONDS,
		"next_tick": now + POOL_TICK_SECONDS}


static func pool_remaining(pool: Dictionary, now: float) -> float:
	if pool.is_empty() or not is_finite(now):
		return 0.0
	var expires: float = float(pool.get("expires", 0.0))
	if not is_finite(expires):
		return 0.0
	return clampf(expires - now, 0.0, POOL_SECONDS)



static func spawn_chance(zone: int) -> float:
	if zone < MIN_ZONE:
		return 0.0
	return 0.08 + 0.04 * float(mini(zone, 3) - MIN_ZONE)


static func can_launch(distance: float) -> bool:
	return is_finite(distance) and distance >= MIN_RANGE and distance <= RANGE


static func hits(center: Vector2, target: Vector3) -> bool:
	if not center.is_finite() or not target.is_finite():
		return false
	var delta := Vector2(target.x, target.z) - center
	return delta.length_squared() <= RADIUS * RADIUS
