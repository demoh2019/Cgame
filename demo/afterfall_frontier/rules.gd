extends RefCounted
## Pure, deterministic gameplay data and rules for the vertical slice.
## All values and names are original. No assets or code from other games.

const WORLD_SIZE = Vector2(1800.0, 1000.0)

const ZONES = [
	{"id": "haven", "name": "HAVEN / Safe settlement", "start": 0.0, "end": 520.0, "danger": 0, "pvp": false, "full_loot": false, "yield": 1},
	{"id": "frontier", "name": "FRONTIER / Contested", "start": 520.0, "end": 1160.0, "danger": 1, "pvp": true, "full_loot": false, "yield": 2},
	{"id": "deadlands", "name": "DEADLANDS / High risk", "start": 1160.0, "end": 1800.0, "danger": 2, "pvp": true, "full_loot": true, "yield": 3},
]

# Compact item registry; the same IDs are used by gathering, inventory,
# persistence, trading and crafting. All generated/loaded items are whitelisted.
const ITEMS = {
	"wood": {"name": "Wood", "weight": 1, "value": 2},
	"stone": {"name": "Stone", "weight": 1, "value": 2},
	"fiber": {"name": "Fiber", "weight": 1, "value": 3},
	"herb": {"name": "Healing herb", "weight": 1, "value": 4},
	"water": {"name": "Clean water", "weight": 1, "value": 5},
	"food": {"name": "Rations", "weight": 1, "value": 5},
	"scrap": {"name": "Scrap metal", "weight": 2, "value": 6},
	"ore": {"name": "Iron ore", "weight": 2, "value": 9},
	"alloy": {"name": "Rare alloy", "weight": 2, "value": 25},
	"axe": {"name": "Survival axe", "weight": 3, "value": 14},
	"pickaxe": {"name": "Mining pickaxe", "weight": 3, "value": 20},
	"spear": {"name": "Reinforced spear", "weight": 4, "value": 26},
	"bandage": {"name": "Bandage", "weight": 1, "value": 11},
	"armor": {"name": "Scrap armor", "weight": 6, "value": 46},
}

# Crafting recipes have explicit station gating and profession XP.
const RECIPES = {
	"axe": {"cost": {"wood": 3, "stone": 2}, "station": false, "xp": 6},
	"pickaxe": {"cost": {"wood": 3, "stone": 3, "scrap": 2}, "station": true, "xp": 10},
	"spear": {"cost": {"wood": 4, "scrap": 3}, "station": true, "xp": 12},
	"bandage": {"cost": {"fiber": 3, "herb": 1}, "station": false, "xp": 5},
	"armor": {"cost": {"scrap": 5, "fiber": 4, "alloy": 1}, "station": true, "xp": 20},
}

const BASE_WOOD = 8
const BASE_STONE = 6
const STACK_LIMIT = 99
const MAX_CARRY_WEIGHT = 90

static func zone_index(world_x: float) -> int:
	if world_x < float(ZONES[1]["start"]):
		return 0
	if world_x < float(ZONES[2]["start"]):
		return 1
	return 2


static func zone_info(index: int) -> Dictionary:
	return ZONES[clampi(index, 0, ZONES.size() - 1)]


static func item_value(item_id: String) -> int:
	if not ITEMS.has(item_id):
		return 0
	return int(ITEMS[item_id]["value"])


static func item_weight(item_id: String) -> int:
	if not ITEMS.has(item_id):
		return 0
	return int(ITEMS[item_id]["weight"])


static func profession_level(xp: int) -> int:
	# Progressively slower tier advancement and deterministic thresholds.
	return mini(10, int(sqrt(float(maxi(0, xp)) / 12.0)))


static func gathering_yield(zone: int, xp: int) -> int:
	# Safe zone has starter resources; dangerous zones give more per node.
	return int(zone_info(zone)["yield"]) + int(profession_level(xp) / 3)


static func can_gather(item_id: String, inventory: Dictionary) -> bool:
	if not ITEMS.has(item_id):
		return false
	if item_id == "ore":
		return int(inventory.get("pickaxe", 0)) > 0
	if item_id == "alloy":
		return int(inventory.get("pickaxe", 0)) > 0
	return item_id in ["wood", "stone", "fiber", "herb", "water", "food", "scrap"]


static func sanitize_bag(raw: Variant) -> Dictionary:
	# Never trust save-file keys or quantities.
	var bag := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return bag
	for item_id in ITEMS.keys():
		var quantity: Variant = raw.get(item_id, 0)
		if typeof(quantity) in [TYPE_INT, TYPE_FLOAT]:
			var count: int = clampi(int(quantity), 0, STACK_LIMIT)
			if count > 0:
				bag[item_id] = count
	return bag
