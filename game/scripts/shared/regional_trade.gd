extends RefCounted
## Village-specific, deterministic NPC resource demand. The server selects
## the trade station from world geometry; clients never submit a price.
const Vendor = preload("res://scripts/shared/vendor.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const MAX_PREMIUM_PERCENT := 75
const FOCUS := ["fish", "ore", "fiber", "wood", "stone"]


static func category(item_id: String) -> String:
	if item_id == "raw_fish" or item_id.begins_with("raw_fish_"):
		return "fish"
	for kind in ["ore", "fiber", "wood", "stone"]:
		if item_id.begins_with(kind + "_"):
			return kind
	return ""


static func offer_for_site(site: Dictionary) -> Dictionary:
	if site.is_empty() or not bool(site.get("station", false)):
		return {}
	var seed: int = int(site.get("seed", -1))
	if seed < 0 or not site.has("zone") or not site.has("display"):
		return {}
	var zone: int = int(site["zone"])
	if zone < 0 or zone > 3:
		return {}
	# Fixed world-seed / site identity: no time-based rerolls or client bidding.
	var premium: int = mini(MAX_PREMIUM_PERCENT, 35 + zone * 10 + (seed % 3) * 5)
	return {"name": str(site["display"]), "category": FOCUS[seed % FOCUS.size()],
		"premium_percent": premium, "zone": zone}


## Valid only while actually standing beside the procedurally generated
## trader/workbench. The central safe hub retains ordinary vendor prices.
static func local_offer(world, position: Vector3) -> Dictionary:
	if not position.is_finite() or world.is_safe(position.x, position.z):
		return {}
	var site: Dictionary = world.poi.site_at(position.x, position.z)
	if site.is_empty() or not bool(site.get("station", false)):
		return {}
	var at := Vector2(position.x, position.z)
	if at.distance_to(Vector2(float(site["station_x"]), float(site["station_z"]))) > WorldPoi.STATION_RANGE:
		return {}
	return offer_for_site(site)


static func sell_price(item_id: String, offer: Dictionary) -> int:
	var base_price: int = int(Vendor.SELL_PRICES.get(item_id, 0))
	if base_price <= 0:
		return 0
	if offer.is_empty() or category(item_id) != str(offer.get("category", "")):
		return base_price
	var premium: int = clampi(int(offer.get("premium_percent", 0)), 0, MAX_PREMIUM_PERCENT)
	return ceili(float(base_price) * (100.0 + premium) / 100.0)


static func public_offer(world, position: Vector3) -> Dictionary:
	var offer: Dictionary = local_offer(world, position)
	if offer.is_empty():
		return {}
	return {"name": offer["name"], "category": offer["category"],
		"premium_percent": offer["premium_percent"]}
