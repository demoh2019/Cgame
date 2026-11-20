extends RefCounted
## Server-issued temporary footstep muffling; sound is not invisibility.
const ITEM_ID := "soft_sole_wraps"
const DURATION_SECONDS := 90.0
const SPRINT_NOISE_FACTOR := 0.55


static func valid_remaining(seconds: Variant) -> bool:
	if not (seconds is float or seconds is int):
		return false
	return is_finite(float(seconds)) and float(seconds) >= 0.0 and float(seconds) <= DURATION_SECONDS


## Affects only NEW sprint noise; never reduce an already loud sound source.
static func sprint_noise(normal_radius: float, seconds: float) -> float:
	if not is_finite(normal_radius) or normal_radius < 0.0:
		return 0.0
	if not valid_remaining(seconds) or seconds <= 0.0:
		return normal_radius
	return normal_radius * SPRINT_NOISE_FACTOR
