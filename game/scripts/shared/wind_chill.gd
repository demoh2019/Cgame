extends RefCounted
## Regional wind chill joins the seeded wind model and persistent survival.
## All inputs are obtained from the server-owned world, position and gear.

const Weather = preload("res://scripts/shared/weather.gd")
const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")
const MIN_WIND_MPS := 0.35
const FULL_WIND_MPS := 1.6
const COLD_RANGE_C := 18.0
const MAX_EXTRA_SEVERITY := 0.22
const WET_AMPLIFIER := 0.50


## Additional 0..0.33 exposure intensity. Calm/warm or covered hub weather
## gives zero; wet clothes amplify gusts, protective armor mitigates them.
static func penalty(conditions: Dictionary, wind: Vector2, wetness: float,
		armor_id: String) -> float:
	if conditions.is_empty() or bool(conditions.get("sheltered", false)) or \
			not wind.is_finite() or not is_finite(wetness):
		return 0.0
	var temperature_c: float = float(conditions.get("temperature_c", NAN))
	if not is_finite(temperature_c) or temperature_c >= Weather.COLD_START_C:
		return 0.0
	var speed: float = wind.length()
	if speed <= MIN_WIND_MPS:
		return 0.0
	var cold: float = clampf((Weather.COLD_START_C - temperature_c) / COLD_RANGE_C, 0.0, 1.0)
	var gust: float = clampf((speed - MIN_WIND_MPS) / (FULL_WIND_MPS - MIN_WIND_MPS), 0.0, 1.0)
	var damp: float = clampf(wetness / 100.0, 0.0, 1.0)
	return MAX_EXTRA_SEVERITY * cold * gust * (1.0 + WET_AMPLIFIER * damp) * \
		(1.0 - Weather.protection(armor_id))


## A view of the viewer's own verified local weather. Not a state change or
## remotely supplied damage. The numbers reflect tarp/fire protection to
## avoid displaying a penalty that a shelter has already neutralized.
static func visible(world, position: Vector3, now: float, wetness: float,
		armor_id: String, near_fire: bool = false, under_tarp: bool = false) -> Dictionary:
	if not position.is_finite() or not is_finite(now):
		return {"speed": 0.0, "extra": 0.0}
	var conditions: Dictionary = Weather.conditions(world, position.x, position.z, now)
	var wind: Vector2 = Weather.wind_at(world, position.x, position.z, now)
	var extra: float = penalty(conditions, wind, wetness, armor_id)
	if near_fire:
		extra = 0.0
	else:
		extra = PortableShelter.exposure_severity(extra, under_tarp)
	return {"speed": wind.length(), "extra": extra}
