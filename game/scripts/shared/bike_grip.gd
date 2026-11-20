extends RefCounted
## Consumable off-road bicycle tread kit. Both server and client use the same
## deterministic surface modifier, without changing slopes, obstacles or sprint.

const ITEM_ID := "trail_tire_grips"
const BIKE_ID := "salvage_bike"
const DURATION_SECONDS := 240.0
const RECOVERY_SHARE := 0.50


static func apply_reason(inventory, seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0 or seconds > DURATION_SECONDS:
		return "invalid_state"
	if inventory.count(BIKE_ID) < 1:
		return "missing_bike"
	if seconds > 0.0:
		return "already_gripped"
	return ""


static func active(seconds: float) -> bool:
	return is_finite(seconds) and seconds > 0.0 and seconds <= DURATION_SECONDS


## Restore half of the loss from a rough surface, but never add free speed
## on firm ground, ignore slope resistance or bypass water/wall collision.
static func surface_factor(biome: String, base: float, seconds: float) -> float:
	if not is_finite(base) or base < 0.0 or base > 1.0:
		return base
	if not active(seconds):
		return base
	if biome not in ["swamp", "beach", "forest", "mountain"]:
		return base
	return base + (1.0 - base) * RECOVERY_SHARE
