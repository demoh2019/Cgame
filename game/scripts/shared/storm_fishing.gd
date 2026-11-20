extends RefCounted
## Optional high-risk fishing: server weather, risk and catch sizes only.
const Weather = preload("res://scripts/shared/weather.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const CAST_SECONDS := 8.0
const BONUS_FISH := 2
const MIN_FREE_FISH := 3


static func qualifies(world, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now) or now < 0.0:
		return false
	if not ZoneRisk.full_loot(world.zone_at(position.x, position.z)):
		return false
	var weather: Dictionary = Weather.conditions(world, position.x, position.z, now)
	return str(weather.get("condition", "")) == "storm" and not bool(
		weather.get("sheltered", false))


## Other fish quality gates (zone, profession, rod) are unchanged.
static func bonus_for(backpack, fish_id: String, base_count: int) -> int:
	if backpack == null or base_count < 1 or base_count > Fishing.MAX_CATCH:
		return 0
	if not fish_id.begins_with("raw_fish"):
		return 0
	return BONUS_FISH if backpack.free_space_for(fish_id) >= base_count + BONUS_FISH else 0
