extends RefCounted
## Search/filter and safe bulk-batch previews for the crafting UI.
## Pure local estimates: GameServer.cmd_craft remains the sole authority.

const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")

const MAX_BATCHES := 50


static func matches(recipe_id: String, search: String) -> bool:
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return false
	var haystack := recipe_id.to_lower() + " " + \
		str(Defs.item(str(recipe["output"])).get("name", "")).to_lower()
	for input in recipe["inputs"]:
		haystack += " " + str(input).to_lower() + " " + \
			str(Defs.item(str(input)).get("name", "")).to_lower()
	for term in search.strip_edges().to_lower().split(" ", false):
		if not haystack.contains(term):
			return false
	return true


## Calculate a real transaction-safe maximum, including input stacks and
## output room AFTER consuming materials. Descending scan is deliberate:
## crafting 2 batches can free an input slot where crafting 1 cannot.
static func max_batches(inventory, recipe_id: String) -> int:
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return 0
	var upper: int = MAX_BATCHES
	for input in recipe["inputs"]:
		var needed: int = int(recipe["inputs"][input])
		if needed <= 0:
			return 0
		upper = mini(upper, int(inventory.count(str(input))) / needed)
	if upper < 1:
		return 0
	var data: Dictionary = inventory.to_dict()
	for times in range(upper, 0, -1):
		var trial = Inventory.new(inventory.slots.size())
		trial.load_dict(data)
		if Crafting.craft(trial, recipe_id, true, times, true) == Crafting.Result.OK:
			return times
	return 0


## "Available" means inventory and crafting tier permit the recipe.
## Station proximity, life, mount status and combat remain server-owned.
static func entries(inventory, search: String, ready_only: bool, crafting_level: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for key in Defs.recipes():
		var id: String = str(key)
		if not matches(id, search):
			continue
		var recipe: Dictionary = Defs.recipes()[id]
		var tier: int = maxi(1, Defs.tier_of(str(recipe["output"])))
		var max_count: int = max_batches(inventory, id)
		var locked: bool = tier > crafting_level
		var ready: bool = max_count > 0 and not locked
		if ready_only and not ready:
			continue
		found.append({"id": id, "max_batches": max_count,
			"tier": tier, "skill_locked": locked, "ready": ready})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["ready"]) != bool(b["ready"]):
			return bool(a["ready"])
		return str(a["id"]) < str(b["id"]))
	return found
