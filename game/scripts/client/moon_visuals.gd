extends RefCounted
## Render-only lunar cycle. Authoritative server time is the sole clock:
## joining halfway through a night gives the same moon on every client.
## Keep it independent from combat, visibility and survival simulation.

const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const SYNODIC_DAYS := 29.530588


## 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
## A new world begins with a full moon for a readable first night.
static func phase_at(world_seconds: float) -> float:
	if not is_finite(world_seconds):
		return 0.5
	var days: float = world_seconds / WorldCycle.DAY_LENGTH
	return fposmod(days / SYNODIC_DAYS + 0.5, 1.0)


static func illuminated_fraction(phase: float) -> float:
	if not is_finite(phase):
		return 1.0
	return 0.5 - 0.5 * cos(fposmod(phase, 1.0) * TAU)


## Never extinguish existing moonlit gameplay scenery: the moon phase
## modulates only the artistic directional fill, not ambient night lighting.
static func directional_fill(phase: float) -> float:
	return lerpf(0.65, 1.0, illuminated_fraction(phase))
