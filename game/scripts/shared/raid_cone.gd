extends RefCounted
## Server-only raid warlord directional cleave, locked when telegraphed.
## No client controls aim, hit positions, angle, damage or attack timings.

const REACH := 13.0
const HEIGHT_LIMIT := 3.5
const HALF_ANGLE_DEGREES := 38.0
const MIN_AIM_DISTANCE := 0.4
const WINDUP_SECONDS := 2.2
const FIRST_COOLDOWN := 22.0
const ENRAGED_COOLDOWN := 15.0
const FIRST_DAMAGE := 24.0
const ENRAGED_DAMAGE := 33.0


static func can_aim(origin: Vector3, target: Vector3) -> bool:
	if not origin.is_finite() or not target.is_finite():
		return false
	if absf(origin.y - target.y) > HEIGHT_LIMIT:
		return false
	var relative := Vector2(target.x - origin.x, target.z - origin.z)
	var distance_squared := relative.length_squared()
	return distance_squared >= MIN_AIM_DISTANCE * MIN_AIM_DISTANCE and \
		distance_squared <= REACH * REACH


static func direction(origin: Vector3, target: Vector3) -> Vector2:
	if not can_aim(origin, target):
		return Vector2.ZERO
	return Vector2(target.x - origin.x, target.z - origin.z).normalized()


static func in_sector(origin: Vector3, aim: Vector2, victim: Vector3) -> bool:
	if not origin.is_finite() or not aim.is_finite() or not victim.is_finite():
		return false
	if absf(origin.y - victim.y) > HEIGHT_LIMIT:
		return false
	if absf(aim.length_squared() - 1.0) > 0.01:
		return false
	var relative := Vector2(victim.x - origin.x, victim.z - origin.z)
	if relative.length_squared() > REACH * REACH:
		return false
	if relative.length_squared() <= 0.0001:
		return true
	return aim.dot(relative.normalized()) >= cos(deg_to_rad(HALF_ANGLE_DEGREES))


static func cooldown(boss) -> float:
	return ENRAGED_COOLDOWN if boss != null and boss.raid_enraged else FIRST_COOLDOWN


static func damage(boss) -> float:
	return ENRAGED_DAMAGE if boss != null and boss.raid_enraged else FIRST_DAMAGE
