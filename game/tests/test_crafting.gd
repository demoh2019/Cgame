extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")


func run(t) -> void:
	t.current = "station"
	var inv := Inventory.new()
	inv.add("wood_1", 10)
	t.eq(Crafting.craft(inv, "plank_1", false), Crafting.Result.NO_STATION, "planks need a workbench")
	t.eq(inv.count("wood_1"), 10, "a refused craft changes nothing")
	t.eq(Crafting.craft(inv, "plank_1", true), Crafting.Result.OK, "planks at the workbench")
	t.eq(inv.count("wood_1"), 8, "two wood used")
	t.eq(inv.count("plank_1"), 1, "one plank made")

	t.current = "batches"
	t.eq(Crafting.craft(inv, "plank_1", true, 4), Crafting.Result.OK, "four batches")
	t.eq(inv.count("plank_1"), 5, "five planks")
	t.eq(inv.count("wood_1"), 0, "all wood used")
	t.eq(Crafting.craft(inv, "plank_1", true), Crafting.Result.MISSING_INPUTS, "no wood left")

	t.current = "no station needed"
	var small := Inventory.new()
	small.add("cloth_1", 4)
	t.eq(Crafting.craft(small, "bandage", false), Crafting.Result.OK, "bandages can be made anywhere")
	t.eq(small.count("bandage"), 2, "a bandage recipe makes two")
	t.eq(Crafting.craft(small, "nonsense", true), Crafting.Result.UNKNOWN_RECIPE, "unknown recipe")

	t.current = "progression"
	# A full tier 1 chain: wood and stone -> planks -> axe; ore -> bars; bars + planks -> tier 2 tools.
	var chain := Inventory.new()
	chain.add("wood_1", 20)
	chain.add("stone_1", 10)
	chain.add("ore_2", 10)
	chain.add("wood_2", 10)
	t.eq(Crafting.craft(chain, "plank_1", true, 4), Crafting.Result.OK, "tier 1 planks")
	t.eq(Crafting.craft(chain, "axe_1", true), Crafting.Result.OK, "a tier 1 axe from planks and stone")
	t.check(chain.count("axe_1") == 1, "the axe exists")
	t.eq(Crafting.craft(chain, "axe_2", true), Crafting.Result.MISSING_INPUTS, "a tier 2 axe needs tier 2 planks and bars")
	t.eq(Crafting.craft(chain, "plank_2", true, 2), Crafting.Result.OK, "tier 2 planks")
	t.eq(Crafting.craft(chain, "bar_2", true, 2), Crafting.Result.OK, "tier 2 bars")
	t.eq(Crafting.craft(chain, "axe_2", true), Crafting.Result.OK, "a tier 2 axe")
	t.eq(Crafting.craft(chain, "club_2", true), Crafting.Result.MISSING_INPUTS, "the tier 2 planks and bars are used up by the axe")

	t.current = "no space"
	var full := Inventory.new(2)
	full.add("canned_food", 10) # One slot.
	full.add("water_bottle", 10) # Second slot: full, nothing can be added.
	full.add("bandage", 0)
	# A recipe whose inputs are not consumed by freeing a slot cannot fit its output.
	var tight := Inventory.new(1)
	tight.add("wood_1", 100)
	tight.add("stone_1", 0)
	t.eq(Crafting.craft(tight, "plank_1", true, 50), Crafting.Result.OK, "100 wood becomes 50 planks in the freed slot")
	var stuck := Inventory.new(2)
	stuck.add("wood_1", 2)
	stuck.add("water_bottle", 10)
	t.eq(Crafting.craft(stuck, "plank_1", true), Crafting.Result.OK, "the freed slot takes the plank")
	var jammed := Inventory.new(2)
	jammed.add("cloth_1", 4)
	jammed.add("stone_1", 100)
	# Both slots are in use, but the four cloth are the whole first stack: using it frees the slot
	# the jacket needs.
	t.eq(Crafting.craft(jammed, "jacket_1", true), Crafting.Result.OK, "a jacket fits in the slot the cloth freed")
	var blocked := Inventory.new(2)
	blocked.add("cloth_1", 100)
	blocked.add("stone_1", 100)
	t.eq(Crafting.craft(blocked, "jacket_1", true), Crafting.Result.NO_SPACE, "a full inventory cannot take the jacket")
	t.eq(blocked.count("cloth_1"), 100, "and the cloth stays")
	var overflow := Inventory.new(1)
	overflow.add("cloth_1", 5)
	overflow.add("bandage", 0)
	# Two batches of bandages need 4 cloth (leaves 1) and make 4 bandages: fits in 1 slot of 10? the slot holds the leftover cloth.
	t.eq(Crafting.craft(overflow, "bandage", false, 2), Crafting.Result.NO_SPACE, "the output does not fit next to the leftover cloth")
	t.eq(overflow.count("cloth_1"), 5, "an impossible craft is undone completely")
	t.eq(overflow.count("bandage"), 0, "and produced nothing")

	t.current = "craftable list"
	var stock := Inventory.new()
	stock.add("wood_1", 2)
	stock.add("cloth_1", 2)
	var craftable := Crafting.craftable(stock)
	t.check(craftable.has("plank_1") and craftable.has("bandage"), "plank and bandage are craftable")
	t.check(not craftable.has("axe_1"), "an axe is not")
