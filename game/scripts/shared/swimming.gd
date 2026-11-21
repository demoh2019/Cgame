extends RefCounted
## Swimming and diving for survivors on foot. Shared by the authoritative server
## and client prediction (Movement.step), so both agree where a swimmer is.
## Deep water used to be a wall; now survivors swim at the surface and dive while
## crouching. Diving uses breath; at zero breath the survivor drowns. Infected
## and bicycles still cannot enter deep water.

const Defs = preload("res://scripts/shared/defs.gd")

const SWIM_DEPTH := 1.0 # Deeper than this, feet leave the bottom.
const SURFACE_BODY := 1.25 # Body (feet) sits this far below the surface: head stays above water.
const DIVE_DEPTH := 3.6 # A diver's body sinks this far below the surface (or to the bottom).
const SWIM_SPEED_FACTOR := 0.62
const DIVE_SPEED_FACTOR := 0.55

const MAX_BREATH := 100.0
const BREATH_DRAIN := 8.5 # Per second underwater: about 12 s of air.
const BREATH_REFILL := 35.0 # Per second with the head above water.
const DROWN_DAMAGE := 12.0 # Health per second once breath runs out.

# Underwater dangers outside safe water: eels and snagging debris bite divers.
const EEL_MIN_ZONE := 1
const EEL_CHANCE_PER_SECOND := 0.07
const EEL_DAMAGE_PER_ZONE := 7.0


static func depth_at(world, x: float, z: float) -> float:
	if world == null:
		return 0.0
	var ground: float = float(world.height_at(x, z))
	return Defs.WATER_LEVEL - ground if is_finite(ground) else 0.0


static func is_swimming(world, x: float, z: float) -> bool:
	return depth_at(world, x, z) > SWIM_DEPTH


## Height of the swimmer's feet: near the surface, or deeper while diving, never below the bottom.
static func body_y(world, x: float, z: float, diving: bool) -> float:
	var ground: float = float(world.height_at(x, z))
	var target: float = Defs.WATER_LEVEL - (DIVE_DEPTH if diving else SURFACE_BODY)
	return maxf(ground + 0.15, target)


## Whether the swimmer's head is under the surface.
static func submerged(world, x: float, z: float, diving: bool) -> bool:
	return diving and is_swimming(world, x, z)


static func speed_factor(diving: bool) -> float:
	return DIVE_SPEED_FACTOR if diving else SWIM_SPEED_FACTOR


## Next breath value and the drowning damage taken over `delta`.
static func breathe(breath: float, underwater: bool, delta: float) -> Vector2:
	delta = maxf(0.0, delta)
	if not underwater:
		return Vector2(minf(MAX_BREATH, breath + BREATH_REFILL * delta), 0.0)
	var drained: float = breath - BREATH_DRAIN * delta
	if drained >= 0.0:
		return Vector2(drained, 0.0)
	# Only the part of the tick spent without air hurts.
	var airless: float = -drained / BREATH_DRAIN
	return Vector2(0.0, DROWN_DAMAGE * minf(airless, delta))


## Eel bite chance this tick for a diver in a dangerous zone (0 when safe).
static func eel_chance(zone: int, safe: bool, delta: float) -> float:
	if safe or zone < EEL_MIN_ZONE:
		return 0.0
	return clampf(EEL_CHANCE_PER_SECOND * float(zone) * maxf(0.0, delta), 0.0, 1.0)


static func eel_damage(zone: int) -> float:
	return EEL_DAMAGE_PER_ZONE * float(maxi(zone, 1))
