extends RefCounted
## The raid warlord exposes its armor after a confirmed slam.
## All timing, target identity and damage decisions are server-authoritative.

const NORMAL_SECONDS := 4.0
const ENRAGED_SECONDS := 2.5
const DAMAGE_BONUS := 0.15


static func window_seconds(boss) -> float:
	if boss == null or not boss.raid_boss or not boss.is_alive():
		return 0.0
	return ENRAGED_SECONDS if boss.raid_enraged else NORMAL_SECONDS


static func remaining(boss, exposed_until: float, now: float) -> float:
	if not is_finite(exposed_until) or not is_finite(now) or exposed_until <= now:
		return 0.0
	var duration: float = window_seconds(boss)
	if duration <= 0.0:
		return 0.0
	return clampf(exposed_until - now, 0.0, duration)


## Only called in the server's infected branch, for the current raid boss.
static func amplify(damage: float, boss, exposed_until: float, now: float) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	if remaining(boss, exposed_until, now) <= 0.0:
		return damage
	return damage * (1.0 + DAMAGE_BONUS)
