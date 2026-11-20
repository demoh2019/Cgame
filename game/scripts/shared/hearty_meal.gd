extends RefCounted
## Classless cooked-meal bonus. Server owns the food, duration, tick and save.
## Food only enhances recovery while hydrated and nourished; it never heals
## wounds or raises stamina/combat energy over their existing caps.

const Defs = preload("res://scripts/shared/defs.gd")

const MAX_DURATION := 210.0


static func tier_for_food(item_id: String) -> int:
	if item_id == "cooked_fish":
		return 1
	for tier in range(2, Defs.MAX_TIER + 1):
		if item_id == "cooked_fish_%d" % tier:
			return tier
	return 0


static func duration(tier: int) -> float:
	if tier < 1 or tier > Defs.MAX_TIER:
		return 0.0
	return 90.0 + 30.0 * float(tier)


static func stamina_per_second(tier: int) -> float:
	return 1.5 + 0.5 * float(tier) if tier >= 1 and tier <= Defs.MAX_TIER else 0.0


static func energy_per_second(tier: int) -> float:
	return 0.5 + 0.25 * float(tier) if tier >= 1 and tier <= Defs.MAX_TIER else 0.0


## The rank and time must be consistent, with strict types and finite numbers.
## Zero-time, zero-rank is the only inactive state. Legacy saves default to it.
static func valid_state(seconds: Variant, tier: Variant) -> bool:
	if not (seconds is float or seconds is int) or not (tier is int):
		return false
	var remaining: float = float(seconds)
	if not is_finite(remaining) or remaining < 0.0 or remaining > MAX_DURATION:
		return false
	if remaining == 0.0:
		return tier == 0
	return tier >= 1 and tier <= Defs.MAX_TIER and remaining <= duration(int(tier))


## Integrate only seconds that the buff is actually active (even with big ticks).
## Recovery is blocked by starvation/dehydration and stamina recovery delay.
static func bonus_seconds(seconds: float, delta: float) -> float:
	return minf(maxf(0.0, seconds), maxf(0.0, delta))


static func stamina_seconds(active_seconds: float, recovery_delay: float) -> float:
	return maxf(0.0, active_seconds - maxf(0.0, recovery_delay))
