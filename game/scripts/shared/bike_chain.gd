extends RefCounted
## Bicycle hearing is a tradeoff for mounted travel speed. Only a consumed kit
## lowers the radius; gunshots, footfalls, scent and visibility remain unchanged.

const Mounts = preload("res://scripts/shared/mounts.gd")
const ITEM_ID := "bike_chain_wrap"
const DURATION_SECONDS := 180.0
const RIDING_NOISE_RADIUS := Mounts.NOISE_RADIUS
const WRAPPED_NOISE_RADIUS := 9.0
const SOUND_SECONDS := Mounts.NOISE_SECONDS


static func apply_reason(inventory, remaining: float) -> String:
	if not is_finite(remaining) or remaining < 0.0 or remaining > DURATION_SECONDS:
		return "invalid_state"
	if inventory.count(Mounts.ITEM_ID) < 1:
		return "missing_bike"
	if remaining > 0.0:
		return "already_wrapped"
	return ""


static func riding_radius(remaining: float) -> float:
	return WRAPPED_NOISE_RADIUS if is_finite(remaining) and remaining > 0.0 else RIDING_NOISE_RADIUS
