extends RefCounted
## Server-side diminishing returns for repeated PvE staggers.
## This does not affect roots, knockback, combat damage, players or raid bosses.

const RESET_SECONDS := 6.0
const MAX_STACKS := 3
const FACTORS := [1.0, 0.65, 0.40]


static func duration(base: float, stacks: int, elite: bool) -> float:
	if not is_finite(base) or base <= 0.0 or base > 1.5:
		return 0.0
	var factor: float = FACTORS[clampi(stacks, 0, MAX_STACKS - 1)]
	return base * factor * (0.5 if elite else 1.0)


static func remaining(seconds: float, delta: float) -> float:
	if not is_finite(seconds) or not is_finite(delta) or seconds <= 0.0 or delta <= 0.0:
		return maxf(0.0, seconds) if is_finite(seconds) else 0.0
	return maxf(0.0, seconds - delta)
