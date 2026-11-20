extends RefCounted
## Weight makes walking under a heavy backpack conspicuous in the wilderness.
## The authoritative server computes both load and real distance travelled.
## No client-defined noise, extra inventory slots, or persistent modifiers.

const Defs = preload("res://scripts/shared/defs.gd")
const NOISE_SECONDS := 0.7
const MIN_RADIUS := 10.0
const MAX_RADIUS := 24.0


## Returns server-created detection radius, or zero when there is no
## actual movement, load penalty, or when the traveler crouches / rides.
## The returned radius is combined with other sounds using max(), never added.
static func radius(movement_factor: float, moved_meters: float,
		crouching: bool, mounted: bool) -> float:
	if not is_finite(movement_factor) or not is_finite(moved_meters) or \
			moved_meters <= 0.0001 or crouching or mounted or movement_factor >= 0.9999:
		return 0.0
	var load_fraction: float = clampf(
		(1.0 - movement_factor) / (1.0 - Defs.CARRY_MIN_SPEED_FACTOR), 0.0, 1.0)
	return lerpf(MIN_RADIUS, MAX_RADIUS, load_fraction)
