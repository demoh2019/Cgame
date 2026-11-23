extends RefCounted
## Distinguish exploration caches without extra scene nodes or draw calls.
## Client rendering only: authoritative loot and collision remain unchanged.


static func tint(crate: Dictionary) -> Color:
	if bool(crate.get("roadside_cache", false)):
		return Color(0.98, 0.78, 0.44) # Dusty amber travel supplies.
	if bool(crate.get("urban_cache", false)):
		return Color(0.64, 0.86, 0.98) # Weathered blue-gray city salvage.
	return Color.WHITE
