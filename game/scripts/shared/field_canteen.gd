extends RefCounted
## One-use carbon filtration with a permanent carried canteen.
## The server owns the shore and cooldown checks; this helper provides an
## atomic backpack conversion so a full bag never loses a filter.

const Inventory = preload("res://scripts/shared/inventory.gd")
const CANTEEN_ITEM := "field_canteen"
const FILTER_ITEM := "charcoal_filter"
const OUTPUT_ITEM := "water_bottle"
const OUTPUT_COUNT := 1


static func fill(backpack) -> String:
	if backpack == null or backpack.count(CANTEEN_ITEM) < 1:
		return "need_canteen"
	if backpack.count(FILTER_ITEM) < 1:
		return "need_filter"
	var staged = Inventory.new(backpack.slots.size())
	staged.load_dict(backpack.to_dict())
	if not staged.remove(FILTER_ITEM, 1):
		return "need_filter"
	if staged.add(OUTPUT_ITEM, OUTPUT_COUNT) != 0:
		return "no_space"
	# Commit the whole transaction only after the water will fit.
	backpack.load_dict(staged.to_dict())
	return ""
