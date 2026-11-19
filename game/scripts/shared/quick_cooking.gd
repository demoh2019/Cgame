extends RefCounted
## A recipe suggestion only. The server remains authoritative about stations,
## surviving, inventory mutations, quantity and permanent crafting mastery.
const Defs = preload("res://scripts/shared/defs.gd")


## Highest tier first. Skips locked recipes or missing ingredients, but never
## substitutes a field campfire for the required server-side station check.
static func best_recipe(inventory, crafting_level: int) -> String:
	for tier in range(Defs.MAX_TIER, 0, -1):
		if tier > crafting_level:
			continue
		var recipe_id: String = "cooked_fish" if tier == 1 else "cooked_fish_%d" % tier
		var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
		if recipe.is_empty() or recipe.get("station", "") != "campfire":
			continue
		if inventory.has_all(recipe["inputs"]):
			return recipe_id
	return ""
