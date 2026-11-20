extends RefCounted
## Authoritative acoustic cover. Sound already has a server-issued radius and
## wind direction; nearby walls attenuate first passive acquisition only.
## Reuses bullet/vision broadphase, never client physics or replicated targets.
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")

const QUIET_REFERENCE := 21.0
const LOUD_REFERENCE := 32.0
const QUIET_TRANSMISSION := 0.62
const LOUD_TRANSMISSION := 0.80
const END_TOLERANCE := 0.08
# A narrow workbench, grass clump or thin sapling should not act as an
# acoustic brick wall. Bullet/sight collision still respects every blocker.
const ACOUSTIC_MIN_RADIUS := 1.1

static var _native_checked: bool = false
static var _native: Object = null


## Pure GDScript reference matches the optional native SoundPropagation
## engine module. Even gunshots cannot exceed the original wind/leash radius.
static func attenuation_radius(source_radius: float, wind_radius: float,
		blocked: bool) -> float:
	if not is_finite(source_radius) or source_radius <= 0.0 \
			or not is_finite(wind_radius) or wind_radius <= 0.0:
		return 0.0
	if not blocked:
		return wind_radius
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("SoundPropagation"):
			_native = ClassDB.instantiate("SoundPropagation")
	if _native != null and _native.has_method("effective_radius"):
		var result: float = float(_native.call(
			"effective_radius", source_radius, wind_radius, true))
		if is_finite(result) and result >= 0.0 and result <= wind_radius:
			return result
	var balance: float = clampf((source_radius - QUIET_REFERENCE) /
		(LOUD_REFERENCE - QUIET_REFERENCE), 0.0, 1.0)
	return wind_radius * lerpf(QUIET_TRANSMISSION, LOUD_TRANSMISSION, balance)


## One broadphase ray only for marginal acoustic acquisition. At close
## range cover still permits hearing, farther than unobstructed sound no
## ray is necessary. Vision/scent/pack alerts have separate semantics.
static func audible(world, source: Vector3, listener: Vector3,
		source_radius: float, wind_radius: float) -> bool:
	if world == null or not source.is_finite() or not listener.is_finite() \
			or not is_finite(source_radius) or not is_finite(wind_radius) \
			or source_radius <= 0.0 or wind_radius <= 0.0:
		return false
	var from := Vector2(source.x, source.z)
	var to := Vector2(listener.x, listener.z)
	var vector: Vector2 = to - from
	var squared: float = vector.length_squared()
	if not is_finite(squared) or squared > wind_radius * wind_radius:
		return false
	var distance: float = sqrt(squared)
	if distance <= attenuation_radius(source_radius, wind_radius, true):
		return true
	# The same rounded 2D solids that stop bullets and first visual contact,
	# including destructible barricades and static procedural cover.
	return RangedCover.first_blocker_distance(world, from, vector, distance,
		ACOUSTIC_MIN_RADIUS) >= distance - END_TOLERANCE
