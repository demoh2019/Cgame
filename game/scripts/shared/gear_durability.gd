extends RefCounted
## Albion-style gear durability: equipped weapons wear when they hit, worn armor
## wears when it is hit, and a death that keeps your gear (safe zones) still costs
## a chunk of durability. Broken (0%) gear works at half strength until repaired
## for silver at a workbench - the main recurring silver sink of the economy.

const MAX := 100.0
const WEAPON_WEAR_PER_HIT := 0.06
const ARMOR_WEAR_PER_HIT := 0.09
const DEATH_WEAR := 10.0
const BROKEN_EFFECTIVENESS := 0.5
const REPAIR_COST_FRACTION := 0.35 # Silver per item value, for a full 0 -> 100 repair.


## Combat effectiveness of an item at a durability (0..100).
static func effectiveness(durability: float) -> float:
	return BROKEN_EFFECTIVENESS if durability <= 0.0 else 1.0


## Silver to repair `missing` durability points of an item worth `value`.
static func repair_cost(value: float, missing: float) -> int:
	if missing <= 0.0:
		return 0
	return maxi(1, int(ceil(maxf(value, 1.0) * REPAIR_COST_FRACTION * clampf(missing, 0.0, MAX) / MAX)))


static func clamp_durability(value: float) -> float:
	return clampf(value, 0.0, MAX) if is_finite(value) else MAX
