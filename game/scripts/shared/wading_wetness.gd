extends RefCounted
## Shallow-water crossings soak survivors through their real world position.
## Rain, wind chill, cold and the existing character save already use wetness.
## The server never accepts a client-supplied water depth or wetness amount.

const Defs = preload("res://scripts/shared/defs.gd")
const WetClothing = preload("res://scripts/shared/wet_clothing.gd")
const MAX_DEPTH := 1.0 # Movement blocks deeper water.
const BASE_SOAK_PER_SECOND := 1.0
const DEPTH_SOAK_PER_SECOND := 4.0


## Ankle-to-waist water, derived from world terrain (not input).
## Deep water is not walkable and cannot be used for a wetness exploit.
static func depth_at(world, position: Vector3) -> float:
	if world == null or not position.is_finite() or not world.has_method("height_at"):
		return 0.0
	var ground: float = float(world.height_at(position.x, position.z))
	if not is_finite(ground):
		return 0.0
	var depth: float = Defs.WATER_LEVEL - ground
	if depth <= 0.0 or depth > MAX_DEPTH:
		return 0.0
	return depth


## When physically standing in water, neither a roof nor a warm campfire can
## dry clothing. Rain ingress still stacks with immersion. No water means the
## existing weather/campfire drying rules are preserved exactly.
static func after_weather(previous: float, weather_next: float, delta: float,
		depth: float) -> float:
	var old_wet: float = clampf(previous, 0.0, WetClothing.MAX_WETNESS) if is_finite(previous) else 0.0
	var weather_wet: float = clampf(weather_next, 0.0, WetClothing.MAX_WETNESS) if is_finite(weather_next) else old_wet
	if not is_finite(delta) or delta <= 0.0 or not is_finite(depth) or depth <= 0.0:
		return weather_wet
	if depth > MAX_DEPTH:
		return weather_wet
	var soak_rate: float = BASE_SOAK_PER_SECOND + DEPTH_SOAK_PER_SECOND * depth
	return minf(WetClothing.MAX_WETNESS, maxf(old_wet, weather_wet) + soak_rate * delta)
