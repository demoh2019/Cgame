extends RefCounted
## A crafted bicycle lantern makes night travel easier but exposes its rider.
## The server owns toggle state and throttling; client packets contain only item use.

const ITEM_ID := "bike_dynamo_lamp"
const BIKE_ID := "salvage_bike"
const REVEAL_RADIUS := 23.0
const TOGGLE_COOLDOWN := 0.8


static func toggle_reason(inventory, now: float, last_toggle: float) -> String:
	if inventory.count(BIKE_ID) < 1:
		return "missing_bike"
	if inventory.count(ITEM_ID) < 1:
		return "not_carried"
	if not is_finite(now) or not is_finite(last_toggle):
		return "invalid_state"
	if now < last_toggle + TOGGLE_COOLDOWN:
		return "cooldown"
	return ""


static func lit(inventory, mounted: bool, alive: bool, night: bool, enabled: bool = true) -> bool:
	return enabled and mounted and alive and night and inventory.count(BIKE_ID) > 0 \
		and inventory.count(ITEM_ID) > 0


static func reveal_radius(inventory, mounted: bool, alive: bool, night: bool,
		enabled: bool = true) -> float:
	return REVEAL_RADIUS if lit(inventory, mounted, alive, night, enabled) else 0.0
