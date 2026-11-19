extends RefCounted
## Crafting rules: what a recipe needs, whether the player is at a station, and the transaction
## itself (inputs removed and output added, or nothing changes).

const Defs = preload("res://scripts/shared/defs.gd")

enum Result { OK, UNKNOWN_RECIPE, MISSING_INPUTS, NO_STATION, NO_SPACE }


static func can_craft(inventory, recipe_id: String, at_workbench: bool, at_campfire: bool = false) -> int:
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return Result.UNKNOWN_RECIPE
	match String(recipe["station"]):
		"workbench":
			if not at_workbench:
				return Result.NO_STATION
		"campfire":
			if not (at_workbench or at_campfire):
				return Result.NO_STATION
		"":
			pass
		_:
			return Result.NO_STATION
	if not inventory.has_all(recipe["inputs"]):
		return Result.MISSING_INPUTS
	return Result.OK


## Crafts `times` batches. Returns a Result. Atomic: either everything happens or nothing does.
static func craft(inventory, recipe_id: String, at_workbench: bool, times: int = 1, at_campfire: bool = false) -> int:
	times = maxi(times, 1)
	var status := can_craft(inventory, recipe_id, at_workbench, at_campfire)
	if status != Result.OK:
		return status
	var recipe: Dictionary = Defs.recipes()[recipe_id]
	var inputs: Dictionary = {}
	for id in recipe["inputs"]:
		inputs[id] = int(recipe["inputs"][id]) * times
	if not inventory.has_all(inputs):
		return Result.MISSING_INPUTS
	var output_count: int = int(recipe["count"]) * times
	# Take the inputs first, then check the output fits (freed slots may make the room); undo if not.
	var backup: Dictionary = inventory.to_dict()
	for id in inputs:
		inventory.remove(id, inputs[id])
	if inventory.free_space_for(recipe["output"]) < output_count:
		inventory.load_dict(backup)
		return Result.NO_SPACE
	inventory.add(recipe["output"], output_count)
	return Result.OK


## Recipes the inventory could craft right now (ignoring stations), for the UI.
static func craftable(inventory) -> Array:
	var result: Array = []
	for id in Defs.recipes():
		if inventory.has_all(Defs.recipes()[id]["inputs"]):
			result.append(id)
	result.sort()
	return result
