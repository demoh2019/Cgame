extends RefCounted
## Server-owned bicycle frame integrity. Independent of chain servicing and tire grips.
## The inventory bike remains a tradeable item; no client controls repair or damage.

const BIKE_ID := "salvage_bike"
const KIT_ID := "bike_frame_patch"
const MAX_INTEGRITY := 100.0
const REPAIR_POINTS := 45.0
const HIT_DAMAGE := 20.0
const WEAR_PER_METER := 0.025


static func valid(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= MAX_INTEGRITY


static func can_ride(value: float) -> bool:
	return valid(value) and value > 0.0


static func speed_factor(value: float) -> float:
	if not can_ride(value):
		return 0.0
	if value < 25.0:
		return 0.72
	if value < 60.0:
		return 0.86
	return 1.0


static func terrain_wear(biome: String) -> float:
	match biome:
		"swamp", "water":
			return 2.0
		"beach":
			return 1.7
		"mountain":
			return 1.6
		"forest":
			return 1.3
		_:
			return 1.0


static func after_ride(current: float, biome: String, actual_meters: float) -> float:
	if not valid(current):
		return 0.0
	if not is_finite(actual_meters) or actual_meters <= 0.0:
		return current
	var wear: float = minf(MAX_INTEGRITY, actual_meters * \
		WEAR_PER_METER * terrain_wear(biome))
	return maxf(0.0, current - wear)


static func after_hit(current: float) -> float:
	if not valid(current):
		return 0.0
	return maxf(0.0, current - HIT_DAMAGE)


static func repair_reason(inventory, current: float) -> String:
	if inventory.count(BIKE_ID) < 1:
		return "missing_bike"
	if not valid(current):
		return "invalid_condition"
	if current >= MAX_INTEGRITY:
		return "frame_intact"
	if inventory.count(KIT_ID) < 1:
		return "not_carried"
	return ""


static func after_repair(current: float) -> float:
	if not valid(current):
		return 0.0
	return minf(MAX_INTEGRITY, current + REPAIR_POINTS)
