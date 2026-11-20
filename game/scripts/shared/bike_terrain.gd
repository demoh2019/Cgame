extends RefCounted
## Terrain-aware bicycle handling. Used by the SAME movement code on the
## authoritative server and predictive clients. No client-supplied grip values.

const RoadTravel = preload("res://scripts/shared/road_travel.gd")
const SAMPLE_DISTANCE := 2.0
const MIN_TRACTION := 0.40
const MAX_TRACTION := 1.08
const UPHILL_COST := 1.25
const DOWNHILL_GAIN := 0.25


static func surface_factor(biome: String) -> float:
	match biome:
		"swamp":
			return 0.56 # Mud clogs the wheels.
		"beach":
			return 0.72 # Loose sand.
		"forest":
			return 0.90 # Rough roots and brush.
		"mountain":
			return 0.78 # Loose stones.
		"water":
			return 0.52 # Shallow fords (deep water remains impassable).
		_:
			return 1.0 # Firm plains and town ground.


## Direction is normalized to avoid forged input lengths altering grade sampling.
## The sample is from the deterministic, terrain-levelled world on both peers.
static func speed_factor(world, position: Vector3, direction: Vector2) -> float:
	if not position.is_finite() or not direction.is_finite():
		return 1.0
	var surface: float = RoadTravel.bike_surface(
		surface_factor(world.biome_at(position.x, position.z)),
		RoadTravel.coverage(world, position))
	if direction.length_squared() < 0.000001:
		return surface
	var heading: Vector2 = direction.normalized()
	var here: float = world.height_at(position.x, position.z)
	var ahead: float = world.height_at(
		position.x + heading.x * SAMPLE_DISTANCE,
		position.z + heading.y * SAMPLE_DISTANCE)
	if not is_finite(here) or not is_finite(ahead):
		return surface
	var grade: float = (ahead - here) / SAMPLE_DISTANCE
	var slope_factor := 1.0
	if grade > 0.0:
		slope_factor = maxf(0.48, 1.0 - grade * UPHILL_COST)
	else:
		slope_factor = minf(MAX_TRACTION, 1.0 - grade * DOWNHILL_GAIN)
	return clampf(surface * slope_factor, MIN_TRACTION, MAX_TRACTION)
