extends RefCounted
## Craftable, persisted, server-owned shock mitigation; only lightning uses it.
const ITEM_ID := "storm_insulator"
const DURATION_SECONDS := 180.0
const DAMAGE_REDUCTION := 0.60

static func active(seconds: float) -> bool:
	return is_finite(seconds) and seconds > 0.0 and seconds <= DURATION_SECONDS

static func apply_reason(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0 or seconds > DURATION_SECONDS:
		return "invalid_state"
	return "already_insulated" if seconds > 0.0 else ""

static func lightning_damage(base: float, seconds: float) -> float:
	if not is_finite(base) or base <= 0.0:
		return 0.0
	return base * (1.0 - DAMAGE_REDUCTION) if active(seconds) else base

static func remaining(seconds: float, delta: float) -> float:
	if not active(seconds):
		return 0.0
	if not is_finite(delta) or delta < 0.0:
		return seconds
	return maxf(0.0, seconds - delta)
