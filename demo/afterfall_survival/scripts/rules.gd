extends RefCounted
## Data-only rules: all inventory changes happen locally; no server authority is implied.

const RECIPES: Dictionary = {
	"spear": {"wood": 3, "scrap": 1},
	"axe": {"wood": 2, "stone": 2, "scrap": 2},
	"bandage": {"cloth": 2, "berries": 1},
	"campfire": {"wood": 5, "stone": 3},
}
const WEAPONS: Dictionary = {
	"club": {"damage": 9, "range": 46.0, "cooldown": 0.55},
	"spear": {"damage": 18, "range": 80.0, "cooldown": 0.7},
	"axe": {"damage": 26, "range": 59.0, "cooldown": 0.9},
}
const DROPPABLE: Array[String] = ["wood", "stone", "scrap", "cloth", "berries", "water"]


static func can_craft(inventory: Dictionary, recipe: String) -> bool:
	if not RECIPES.has(recipe):
		return false
	for resource in RECIPES[recipe]:
		if int(inventory.get(resource, 0)) < int(RECIPES[recipe][resource]):
			return false
	return true


static func craft(inventory: Dictionary, recipe: String) -> bool:
	if not can_craft(inventory, recipe):
		return false
	for resource in RECIPES[recipe]:
		inventory[resource] = int(inventory.get(resource, 0)) - int(RECIPES[recipe][resource])
	inventory[recipe] = int(inventory.get(recipe, 0)) + 1
	return true


static func lose_unsecured_supplies(inventory: Dictionary) -> Dictionary:
	var lost: Dictionary = {}
	for resource in DROPPABLE:
		var amount: int = int(inventory.get(resource, 0))
		var dropped: int = amount / 2
		if dropped > 0:
			inventory[resource] = amount - dropped
			lost[resource] = dropped
	return lost


static func survival_speed_multiplier(hunger: float, thirst: float) -> float:
	if hunger <= 0.0 or thirst <= 0.0:
		return 0.65
	if hunger < 20.0 or thirst < 20.0:
		return 0.85
	return 1.0


static func weapon_power(weapon: String, combat_level: int) -> int:
	if not WEAPONS.has(weapon):
		return 0
	return int(WEAPONS[weapon]["damage"]) + maxi(0, combat_level - 1) * 2
