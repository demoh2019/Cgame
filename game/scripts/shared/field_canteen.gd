extends RefCounted
## Two server-gated ways to bottle clean shoreline water. This helper performs
## only atomic inventory conversion; GameServer authorizes the lake and fire.

const Inventory = preload("res://scripts/shared/inventory.gd")
const CANTEEN_ITEM := "field_canteen"
const FILTER_ITEM := "charcoal_filter"
const OUTPUT_ITEM := "water_bottle"
const OUTPUT_COUNT := 1
const BOIL_FUEL := "wood_1"
const BOIL_FUEL_COUNT := 2
const BOIL_RADIUS := 3.2
const BOIL_MAX_HEIGHT := 3.0


## Fire placement, expiry and ownership stay on the server. A survivor can
## share a neighbor's burning fire but cannot boil from another elevation.
static func can_boil(campfires: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	for fire in campfires.values():
		var expires: float = float(fire.get("expires", -1.0))
		var x: float = float(fire.get("x", INF))
		var y: float = float(fire.get("y", INF))
		var z: float = float(fire.get("z", INF))
		if not (is_finite(expires) and is_finite(x) and is_finite(y) and is_finite(z)):
			continue
		if expires <= now or absf(position.y - y) > BOIL_MAX_HEIGHT:
			continue
		if Vector2(position.x - x, position.z - z).length_squared() <= BOIL_RADIUS * BOIL_RADIUS:
			return true
	return false


## Traditional filtration: consumes a single charcoal filter.
static func fill(backpack) -> String:
	return _bottle(backpack, FILTER_ITEM, 1, "need_filter")


## Alternative lakeside survival loop: an existing fire plus two units of
## firewood, without using a disposable charcoal filter.
static func boil(backpack) -> String:
	return _bottle(backpack, BOIL_FUEL, BOIL_FUEL_COUNT, "need_wood")


## All-or-nothing debit/credit even if the final bottle will not fit.
## Removing the last source stack may free the slot needed by the bottle.
static func _bottle(backpack, source_item: String, count: int, missing: String) -> String:
	if backpack == null or backpack.count(CANTEEN_ITEM) < 1:
		return "need_canteen"
	if backpack.count(source_item) < count:
		return missing
	var staged = Inventory.new(backpack.slots.size())
	staged.load_dict(backpack.to_dict())
	if not staged.remove(source_item, count):
		return missing
	if staged.add(OUTPUT_ITEM, OUTPUT_COUNT) != 0:
		return "no_space"
	backpack.load_dict(staged.to_dict())
	return ""
