extends RefCounted
## Shared crouching rules: vision reduction is not immunity to sound or combat.
const WALK_MULTIPLIER := 0.55
const VISUAL_MULTIPLIER := 0.60
const MIN_VISUAL := 0.35


static func speed_factor(crouching: bool) -> float:
	return WALK_MULTIPLIER if crouching else 1.0


static func visual_signature(base: float, crouching: bool,
		noise_timer: float, alive: bool = true) -> float:
	if not is_finite(base) or not is_finite(noise_timer):
		return 1.0
	if not alive or noise_timer > 0.0:
		return 1.0
	var visible: float = clampf(base, MIN_VISUAL, 1.0)
	if crouching:
		visible *= VISUAL_MULTIPLIER
	return clampf(visible, MIN_VISUAL, 1.0)
