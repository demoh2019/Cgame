extends RefCounted
## One simulation clock for client lighting and server-side night danger.
## The dedicated server owns time; clients use the time in authoritative snapshots.
## Preserve the online world's original 900-second sunrise-to-sunrise cycle.

const DAY_LENGTH := 900.0
const NIGHT_NOTICE_MULTIPLIER := 1.35


static func phase(world_seconds: float) -> float:
	if not is_finite(world_seconds):
		return 0.0
	return fposmod(world_seconds, DAY_LENGTH) / DAY_LENGTH


static func sun_height(world_seconds: float) -> float:
	return sin(phase(world_seconds) * TAU)


static func daylight(world_seconds: float) -> float:
	return clampf(sun_height(world_seconds) * 2.0 + 0.5, 0.0, 1.0)


static func is_night(world_seconds: float) -> bool:
	return sun_height(world_seconds) < -0.00001


static func notice_multiplier(world_seconds: float) -> float:
	return NIGHT_NOTICE_MULTIPLIER if is_night(world_seconds) else 1.0
