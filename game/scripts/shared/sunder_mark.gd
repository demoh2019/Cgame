extends RefCounted
## Bounded nonstacking PvE vulnerability derived from server-authored hits.
## Expiration uses world time, not client input or far-away zombie AI ticks.

const DURATION := 4.5
const NORMAL_BONUS := 0.18
const ELITE_BONUS := 0.10
const RAID_BOSS_BONUS := 0.06


static func remaining(infected, now: float) -> float:
	if infected == null or not infected.is_alive() or not is_finite(now):
		return 0.0
	var expires: float = infected.sunder_until
	if not is_finite(expires) or expires <= now:
		return 0.0
	return clampf(expires - now, 0.0, DURATION)


static func multiplier(infected, now: float) -> float:
	if remaining(infected, now) <= 0.0:
		return 1.0
	if infected.raid_boss:
		return 1.0 + RAID_BOSS_BONUS
	if infected.elite:
		return 1.0 + ELITE_BONUS
	return 1.0 + NORMAL_BONUS


static func amplify(damage: float, infected, now: float) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	return damage * multiplier(infected, now)
