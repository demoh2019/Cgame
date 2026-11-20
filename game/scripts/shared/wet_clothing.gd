extends RefCounted
## Persistent wet-clothing simulation driven solely by server weather and
## the actual positions of field campfires/tarps. 0=dry, 100=soaked.
const Weather = preload("res://scripts/shared/weather.gd")
const SOAK_PER_SECOND := 0.9
const AIR_DRY_PER_SECOND := 0.16
const SHELTER_DRY_PER_SECOND := 0.55
const FIRE_DRY_PER_SECOND := 2.5
const MAX_COLD_PENALTY := 0.30
const MAX_WETNESS := 100.0


static func next_wetness(current: float, delta: float, conditions: Dictionary,
		armor_id: String, under_tarp: bool, near_fire: bool) -> float:
	if not is_finite(current) or not is_finite(delta):
		return 0.0
	var wet: float = clampf(current, 0.0, MAX_WETNESS)
	if delta <= 0.0:
		return wet
	var step: float = delta
	if near_fire:
		return maxf(0.0, wet - FIRE_DRY_PER_SECOND * step)
	if bool(conditions.get("sheltered", false)) or under_tarp:
		return maxf(0.0, wet - SHELTER_DRY_PER_SECOND * step)
	if str(conditions.get("condition", "")) == "storm":
		var insulation: float = Weather.protection(armor_id)
		# Better coats slow rain ingress but cannot make a player rainproof.
		return minf(MAX_WETNESS, wet +
			SOAK_PER_SECOND * (1.0 - 0.75 * insulation) * step)
	return maxf(0.0, wet - AIR_DRY_PER_SECOND * step)


## Wet clothing adds exposure stress only in actual cold, even if the rain
## has stopped. Existing camp/tarp protections are applied afterwards.
static func cold_penalty(wetness: float, conditions: Dictionary, armor_id: String) -> float:
	if not is_finite(wetness) or wetness <= 0.0 or \
			bool(conditions.get("sheltered", false)):
		return 0.0
	var temperature: float = float(conditions.get("temperature_c", NAN))
	if not is_finite(temperature):
		return 0.0
	var chill: float = clampf((Weather.COLD_START_C - temperature) / 16.0, 0.0, 1.0)
	return MAX_COLD_PENALTY * clampf(wetness / MAX_WETNESS, 0.0, 1.0) * \
		chill * (1.0 - Weather.protection(armor_id))
