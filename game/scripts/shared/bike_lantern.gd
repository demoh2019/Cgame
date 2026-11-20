extends RefCounted
## A crafted bicycle lantern makes night travel easier but exposes its rider.
## Light detection is computed only from the server's physical inventory and
## mounted state. Client snapshots describe the result, never authorize it.

const ITEM_ID := "bike_dynamo_lamp"
const BIKE_ID := "salvage_bike"
const REVEAL_RADIUS := 23.0


static func lit(inventory, mounted: bool, alive: bool, night: bool) -> bool:
	return mounted and alive and night and inventory.count(BIKE_ID) > 0 \
		and inventory.count(ITEM_ID) > 0


static func reveal_radius(inventory, mounted: bool, alive: bool, night: bool) -> float:
	return REVEAL_RADIUS if lit(inventory, mounted, alive, night) else 0.0
