extends RefCounted
## Quick cooking is only a UI recipe selector; the server owns the action.
const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
	t.current = "highest affordable fish, respecting crafting mastery"
	var bag := Inventory.new()
	t.eq(QuickCooking.best_recipe(bag, 4), "", "empty inventory cannot cook")
	bag.add("raw_fish", 2)
	t.eq(QuickCooking.best_recipe(bag, 4), "", "fish without wood is not a recipe")
	bag.add("wood_1", 2)
	t.eq(QuickCooking.best_recipe(bag, 1), "cooked_fish", "T1 meal selected")
	for tier in range(2, Defs.MAX_TIER + 1):
		bag.add("raw_fish_%d" % tier, 1)
		bag.add("wood_%d" % tier, 1)
	t.eq(QuickCooking.best_recipe(bag, 1), "cooked_fish", "untrained player cannot select higher-tier fish")
	t.eq(QuickCooking.best_recipe(bag, 2), "cooked_fish_2", "T2 mastery unlocks quick cooking T2")
	t.eq(QuickCooking.best_recipe(bag, 3), "cooked_fish_3", "T3 mastery unlocks quick cooking T3")
	t.eq(QuickCooking.best_recipe(bag, 4), "cooked_fish_4", "master chooses the most valuable available fish")

	t.current = "recipe suggestion does not perform or bypass crafting"
	var original: Dictionary = bag.to_dict()
	var recipe: String = QuickCooking.best_recipe(bag, 4)
	t.eq(bag.to_dict(), original, "selector cannot spend materials")
	t.eq(Crafting.craft(bag, recipe, false), Crafting.Result.NO_STATION,
		"quick action cannot cook without a real fire or workbench")
	t.eq(bag.to_dict(), original, "denied cooking does not spend ingredients")
	t.eq(Crafting.craft(bag, recipe, false, 1, true), Crafting.Result.OK,
		"server-permitted field station cooks selected high-tier fish")
	t.eq(bag.count("cooked_fish_4"), 1, "quick-selected food is a real usable meal")
	t.eq(QuickCooking.best_recipe(bag, 4), "cooked_fish_3",
		"when high-tier fish is gone, fall back to the next affordable tier")
	t.eq(QuickCooking.best_recipe(bag, 0), "", "no mastery never selects a recipe")
	bag.remove("wood_3", 1)
	t.eq(QuickCooking.best_recipe(bag, 4), "cooked_fish_2",
		"missing ingredient causes fallback without altering the inventory")
