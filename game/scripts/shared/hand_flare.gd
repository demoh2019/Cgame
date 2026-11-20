extends RefCounted
## Fuel-paid night illumination. Server time and authenticated position only.
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const ITEM_ID := "signal_flare"
const BURN_SECONDS := 120.0
const INFECTED_NOTICE := 28.0


static func ignite_reason(seconds: float, now: float, position: Vector3, safe: bool) -> String:
	if not is_finite(seconds) or seconds < 0.0 or seconds > BURN_SECONDS or \
			not is_finite(now) or not position.is_finite():
		return "invalid_state"
	if seconds > 0.0:
		return "already_burning"
	if safe:
		return "safe_zone"
	if not WorldCycle.is_night(now):
		return "daylight"
	return ""


static func lit(seconds: float, alive: bool) -> bool:
	return is_finite(seconds) and seconds > 0.0 and seconds <= BURN_SECONDS and alive


static func infected_radius(seconds: float, alive: bool, night: bool, safe: bool) -> float:
	return INFECTED_NOTICE if lit(seconds, alive) and night and not safe else 0.0


static func remaining(seconds: float, delta: float) -> float:
	if not is_finite(seconds) or not is_finite(delta):
		return 0.0
	return maxf(0.0, clampf(seconds, 0.0, BURN_SECONDS) - maxf(delta, 0.0))
