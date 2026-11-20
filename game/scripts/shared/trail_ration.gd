extends RefCounted
## Durable smoked fish: server-owned light travel ration, never a combat buff.
## The remaining duration is persisted; no client passes a multiplier or tier.
const Defs = preload("res://scripts/shared/defs.gd")

const MAX_DURATION := 390.0


static func tier_for_food(item_id: String) -> int:
	if item_id == "smoked_fish":
		return 1
	for tier in range(2, Defs.MAX_TIER + 1):
		if item_id == "smoked_fish_%d" % tier:
			return tier
	return 0


static func duration(tier: int) -> float:
	return 150.0 + 60.0 * float(tier) if tier >= 1 and tier <= Defs.MAX_TIER else 0.0


static func hunger_savings(tier: int) -> float:
	# T1 25%; T4 40%. Does not change stamina, combat, PvP or injury damage.
	return 0.20 + 0.05 * float(tier) if tier >= 1 and tier <= Defs.MAX_TIER else 0.0


static func valid_state(seconds: Variant, tier: Variant) -> bool:
	if not (seconds is float or seconds is int) or not (tier is int):
		return false
	var remaining: float = float(seconds)
	if not is_finite(remaining) or remaining < 0.0 or remaining > MAX_DURATION:
		return false
	if remaining == 0.0:
		return tier == 0
	return tier >= 1 and tier <= Defs.MAX_TIER and remaining <= duration(tier)


static func active_seconds(remaining: float, delta: float) -> float:
	if not is_finite(remaining) or not is_finite(delta):
		return 0.0
	return minf(maxf(remaining, 0.0), maxf(delta, 0.0))


## Multiplier for a single tick. Integrates the active fraction exactly when
## a buff ends midway through a long tick. 1.0 means ordinary hunger loss.
static func hunger_factor(tier: int, remaining: float, delta: float) -> float:
	if delta <= 0.0 or not is_finite(delta) or not is_finite(remaining):
		return 1.0
	return 1.0 - hunger_savings(tier) * active_seconds(remaining, delta) / delta


## Prefer the highest fish tier that is actually craftable from carried
## ingredients, without bypassing the normal profession skill gate.
static func best_recipe(inventory, crafting_level: int) -> String:
	if inventory == null or inventory.count("fiber_1") < 1:
		return ""
	for tier in range(mini(Defs.MAX_TIER, maxi(crafting_level, 0)), 0, -1):
		var fish: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
		var wood: String = "wood_%d" % tier
		if inventory.count(fish) >= 1 and inventory.count(wood) >= 2:
			return "smoked_fish" if tier == 1 else "smoked_fish_%d" % tier
	return ""
