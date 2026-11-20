extends RefCounted
## Survival choice: raw fish is edible but unsafe; cooked fish is ordinary food.
## Values and tick integration are shared data, never client-provided damage.

const MAX_SEVERITY := 100.0
const NATURAL_RECOVERY_PER_SECOND := 0.125
const THIRST_DRAIN_PER_SECOND := 0.075
const DAMAGE_PER_SECOND := 0.30
const MAX_HUNGER_TO_EAT_RAW := 85.0
const REMEDY_ITEM := "herbal_gut_tonic"


static func raw_fish_tier(item_id: String) -> int:
	if item_id == "raw_fish":
		return 1
	for tier in range(2, 5):
		if item_id == "raw_fish_%d" % tier:
			return tier
	return 0


static func raw_hunger(tier: int) -> float:
	return 10.0 + 4.0 * float(tier) if tier >= 1 and tier <= 4 else 0.0


static func raw_poison(tier: int) -> float:
	return 26.0 + 6.0 * float(tier) if tier >= 1 and tier <= 4 else 0.0


static func can_eat_raw(hunger: float) -> bool:
	return is_finite(hunger) and hunger >= 0.0 and hunger <= MAX_HUNGER_TO_EAT_RAW


static func valid_severity(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and \
		float(value) >= 0.0 and float(value) <= MAX_SEVERITY


## Exact area integration: one 120-second tick matches 120 one-second ticks
## without applying poison damage after the symptom has dissipated.
static func progress(severity: float, delta: float) -> Dictionary:
	if not valid_severity(severity) or not is_finite(delta) or delta <= 0.0:
		return {"remaining": clampf(severity, 0.0, MAX_SEVERITY) if is_finite(severity) else 0.0,
			"extra_thirst": 0.0, "damage": 0.0}
	var active: float = minf(delta, severity / NATURAL_RECOVERY_PER_SECOND)
	var average: float = severity - NATURAL_RECOVERY_PER_SECOND * active * 0.5
	var exposure: float = average * active / MAX_SEVERITY
	return {"remaining": maxf(0.0, severity - NATURAL_RECOVERY_PER_SECOND * delta),
		"extra_thirst": exposure * THIRST_DRAIN_PER_SECOND,
		"damage": exposure * DAMAGE_PER_SECOND}
