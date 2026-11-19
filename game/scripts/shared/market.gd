extends RefCounted
## Settlement NPC fixed quotes; client never chooses price.
const LIMIT := 20
const SELL := {
	"wood_1": 2, "wood_2": 4, "wood_3": 6, "wood_4": 8,
	"stone_1": 2, "stone_2": 4, "stone_3": 6, "stone_4": 8,
	"ore_1": 3, "ore_2": 6, "ore_3": 9, "ore_4": 12,
	"fiber_1": 2, "fiber_2": 4, "fiber_3": 6, "fiber_4": 8,
	"scrap": 5
}
const BUY := {"water_bottle": 12, "canned_food": 18, "bandage": 20}
const PRIORITY := ["scrap", "ore_4", "ore_3", "ore_2", "ore_1",
	"wood_4", "wood_3", "wood_2", "wood_1",
	"stone_4", "stone_3", "stone_2", "stone_1",
	"fiber_4", "fiber_3", "fiber_2", "fiber_1"]


static func price(item_id: String, buying: bool) -> int:
	return int((BUY if buying else SELL).get(item_id, 0))


static func valid(item_id: String, count: int, buying: bool) -> bool:
	return count > 0 and count <= LIMIT and price(item_id, buying) > 0
