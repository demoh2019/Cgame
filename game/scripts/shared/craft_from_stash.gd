extends RefCounted
## Transactional hub-only crafting from carried + banked materials.
## The authoritative server checks hub location, level, life and mount state.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")

const MAX_BATCHES := 50


## Prefer consuming carried ingredients, then banked units. All changes are
## staged in clones until the output has room in the backpack; rollback is
## exact even when the recipe consumes equipped materials or stack slots.
static func craft(carried, protected_bank, recipe_id: String, times: int = 1) -> int:
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return Crafting.Result.UNKNOWN_RECIPE
	if times < 1 or times > MAX_BATCHES:
		return Crafting.Result.MISSING_INPUTS
	var backpack = Inventory.new(carried.slots.size())
	var bank = Inventory.new(protected_bank.slots.size())
	backpack.load_dict(carried.to_dict())
	bank.load_dict(protected_bank.to_dict())
	for item_id in recipe["inputs"]:
		var id: String = str(item_id)
		var wanted: int = int(recipe["inputs"][item_id]) * times
		if wanted < 1 or backpack.count(id) + bank.count(id) < wanted:
			return Crafting.Result.MISSING_INPUTS
		var from_bag: int = mini(backpack.count(id), wanted)
		if from_bag > 0 and not backpack.remove(id, from_bag):
			return Crafting.Result.MISSING_INPUTS
		var from_bank: int = wanted - from_bag
		if from_bank > 0 and not bank.remove(id, from_bank):
			return Crafting.Result.MISSING_INPUTS
	var output: String = str(recipe["output"])
	var amount: int = int(recipe["count"]) * times
	if amount < 1 or backpack.free_space_for(output) < amount:
		return Crafting.Result.NO_SPACE
	if backpack.add(output, amount) != 0:
		return Crafting.Result.NO_SPACE
	backpack.unequip_missing()
	# Commit both sides only after the entire recipe succeeds.
	carried.load_dict(backpack.to_dict())
	protected_bank.load_dict(bank.to_dict())
	return Crafting.Result.OK
