extends RefCounted
## Deterministic settlement-to-settlement NPC delivery routes. No client
## positions, item counts, target IDs or silver rewards are ever trusted.
## Active jobs save only the source's region/ID and the derived destination ID.
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")

const MIN_ROUTE_DISTANCE := 190.0
const MAX_ROUTE_DISTANCE := 900.0
const CARGO_COUNT := 3
const CARGO := {
	"fish": "raw_fish_2", "ore": "ore_2", "fiber": "fiber_2",
	"wood": "wood_2", "stone": "stone_2",
}


static func station_at(world, position: Vector3) -> Dictionary:
	if not position.is_finite():
		return {}
	var site: Dictionary = world.poi.site_at(position.x, position.z)
	if site.is_empty() or not bool(site.get("station", false)):
		return {}
	var here := Vector2(position.x, position.z)
	var bench := Vector2(float(site["station_x"]), float(site["station_z"]))
	if here.distance_to(bench) > WorldPoi.STATION_RANGE:
		return {}
	return site


## Source->destination is immutable for a given world seed and region.
## Prefer the closest qualified settlement, then a stable ID on exact ties.
static func offer_for(world, source: Dictionary) -> Dictionary:
	if source.is_empty() or not bool(source.get("station", false)):
		return {}
	var origin := Vector2(float(source["station_x"]), float(source["station_z"]))
	var selected: Dictionary = {}
	var best_distance: float = INF
	var best_id: int = 2_147_483_647
	for site in world.poi.sites_near(float(source["x"]), float(source["z"]),
			MAX_ROUTE_DISTANCE + 20.0):
		if not bool(site.get("station", false)) or int(site["id"]) == int(source["id"]):
			continue
		var destination := Vector2(float(site["station_x"]), float(site["station_z"]))
		var distance: float = origin.distance_to(destination)
		if distance < MIN_ROUTE_DISTANCE or distance > MAX_ROUTE_DISTANCE:
			continue
		var regional: Dictionary = RegionalTrade.offer_for_site(site)
		if regional.is_empty() or not CARGO.has(str(regional["category"])):
			continue
		var id: int = int(site["id"])
		if distance < best_distance or (is_equal_approx(distance, best_distance) and id < best_id):
			selected = site
			best_distance = distance
			best_id = id
	if selected.is_empty():
		return {}
	var category: String = str(RegionalTrade.offer_for_site(selected)["category"])
	var item: String = str(CARGO[category])
	var destination_zone: int = int(selected["zone"])
	var payout: int = clampi(roundi(30.0 + best_distance / 12.0 +
			float(destination_zone * 10)), 50, 140)
	return {
		"src_rx": int(floor(float(source["x"]) / WorldPoi.REGION_SIZE)),
		"src_rz": int(floor(float(source["z"]) / WorldPoi.REGION_SIZE)),
		"src_id": int(source["id"]), "dst_id": best_id,
		"src_x": float(source["station_x"]), "src_z": float(source["station_z"]),
		"destination": str(selected["display"]), "dst_x": float(selected["station_x"]),
		"dst_z": float(selected["station_z"]), "cargo": item,
		"quantity": CARGO_COUNT, "silver": payout,
		"distance": roundi(best_distance),
	}


static func saved_state(offer: Dictionary) -> Dictionary:
	return {"src_rx": int(offer["src_rx"]), "src_rz": int(offer["src_rz"]),
		"src_id": int(offer["src_id"]), "dst_id": int(offer["dst_id"])}


## Rebuild the canonical offer on every save-load, not arbitrary client data.
## Saves cannot grant free silver, select another route or fake destinations.
static func from_saved(world, state: Variant) -> Dictionary:
	if not (state is Dictionary):
		return {}
	var data: Dictionary = state
	if data.size() != 4:
		return {}
	for key in ["src_rx", "src_rz", "src_id", "dst_id"]:
		if not data.has(key) or not (data[key] is int):
			return {}
	if absi(int(data["src_rx"])) > 32 or absi(int(data["src_rz"])) > 32:
		return {}
	var source: Dictionary = {}
	for site in world.poi.sites_in_region(int(data["src_rx"]), int(data["src_rz"])):
		if int(site["id"]) == int(data["src_id"]) and bool(site.get("station", false)):
			source = site
			break
	if source.is_empty():
		return {}
	var offer: Dictionary = offer_for(world, source)
	if offer.is_empty() or int(offer["dst_id"]) != int(data["dst_id"]):
		return {}
	return offer


static func valid_state(world, state: Variant) -> bool:
	if not (state is Dictionary):
		return false
	if (state as Dictionary).is_empty():
		return true
	return not from_saved(world, state).is_empty()


## Inventory withdrawal plus reward transfer is one atomic server operation.
## No reward if goods are missing or the backpack cannot accept the silver.
static func deliver(carried, offer: Dictionary) -> Dictionary:
	if offer.is_empty() or not CARGO.values().has(str(offer.get("cargo", ""))):
		return {"ok": false, "reason": "invalid_route"}
	var item: String = str(offer["cargo"])
	var quantity: int = int(offer["quantity"])
	var payout: int = int(offer["silver"])
	if quantity != CARGO_COUNT or payout < 50 or payout > 140:
		return {"ok": false, "reason": "invalid_route"}
	var staged := Inventory.new(carried.slots.size())
	staged.load_dict(carried.to_dict())
	if not staged.remove(item, quantity):
		return {"ok": false, "reason": "missing_cargo"}
	if staged.add("silver", payout) != 0:
		return {"ok": false, "reason": "no_space"}
	carried.load_dict(staged.to_dict())
	return {"ok": true, "cargo": item, "quantity": quantity, "silver": payout}
