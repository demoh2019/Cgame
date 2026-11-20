extends RefCounted
## Seeded storms soften exposed ground. Roads retain traction even in rain.
## No state is persisted: both server and client derive the same effect from
## world seed, position and authoritative world time.

const Weather = preload("res://scripts/shared/weather.gd")
const RoadTravel = preload("res://scripts/shared/road_travel.gd")
const ROAD_PROTECTION := 0.85
const FOOT_LOSS := {
	"swamp": 0.18, "forest": 0.12, "mountain": 0.09,
	"beach": 0.08, "plains": 0.07, "water": 0.10,
}
const BIKE_LOSS := {
	"swamp": 0.24, "forest": 0.17, "mountain": 0.12,
	"beach": 0.13, "plains": 0.09, "water": 0.16,
}


## Pure factor. The benefit of a road cannot exceed 85% of the rain loss;
## pre-existing road travel bonuses still apply independently.
static func traction(weather: Dictionary, biome: String, road_coverage: float,
		mounted: bool) -> float:
	if weather.is_empty() or bool(weather.get("sheltered", false)) or \
			str(weather.get("condition", "")) != "storm" or \
			not is_finite(road_coverage):
		return 1.0
	var penalties: Dictionary = BIKE_LOSS if mounted else FOOT_LOSS
	var loss: float = float(penalties.get(biome, 0.0))
	var protection: float = ROAD_PROTECTION * clampf(road_coverage, 0.0, 1.0)
	return clampf(1.0 - loss * (1.0 - protection), 0.70, 1.0)


## Only the server supplies time for authoritative input processing. The
## prediction code uses the most recent replicated server clock instead of
## receiving an untrusted network-supplied traction multiplier.
static func factor(world, position: Vector3, seconds: float, mounted: bool) -> float:
	if world == null or not position.is_finite() or not is_finite(seconds) or \
			not world.has_method("biome_at") or not world.has_method("is_safe"):
		return 1.0
	var current: Dictionary = Weather.conditions(world, position.x, position.z, seconds)
	return traction(current, world.biome_at(position.x, position.z),
		RoadTravel.coverage(world, position), mounted)
