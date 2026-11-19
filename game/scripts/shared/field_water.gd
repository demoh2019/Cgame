extends RefCounted
## Fictional lake-water risk and one-use field filtration.
## The dedicated server checks shore access and owns the contamination outcome.
## No client input controls contamination, reward or the cooldown.

const FILTER_ITEM := "charcoal_filter"
const COOLDOWN_SECONDS := 12.0
const THIRST_RESTORED := 35.0
const UNTREATED_INFECTION := 8.0
const SHORE_REACH := 3.0
const SHORE_SAMPLES := 8


static func can_access_lake(world, position: Vector3) -> bool:
	if not position.is_finite() or world.is_water(position.x, position.z):
		return false
	var here := Vector2(position.x, position.z)
	for index in SHORE_SAMPLES:
		var point := here + Vector2.from_angle(float(index) * TAU / SHORE_SAMPLES) * SHORE_REACH
		if world.is_water(point.x, point.y):
			return true
	return false


static func needs_drink(vitals) -> bool:
	return vitals.alive and is_finite(vitals.thirst) and vitals.thirst <= 95.0
