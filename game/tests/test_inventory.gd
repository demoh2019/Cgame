extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func run(t) -> void:
	t.current = "add and count"
	var inv := Inventory.new(4)
	t.eq(inv.add("wood_1", 30), 0, "adds without overflow")
	t.eq(inv.count("wood_1"), 30, "counts")
	var remainder := inv.add("wood_1", 400)
	t.eq(inv.count("wood_1"), 400, "four slots of 100 hold 400")
	t.eq(remainder, 30, "the part that did not fit is returned")
	t.eq(inv.add("not_an_item", 1), 1, "unknown items are refused")
	t.eq(inv.add("wood_1", 0), 0, "adding nothing is fine")

	t.current = "remove"
	t.check(not inv.remove("wood_1", 500), "cannot remove more than is there")
	t.eq(inv.count("wood_1"), 400, "a failed remove changes nothing")
	t.check(inv.remove("wood_1", 150), "removes across stacks")
	t.eq(inv.count("wood_1"), 250, "count after remove")
	t.check(inv.remove("wood_1", 250), "removes everything")
	var all_empty := true
	for slot in inv.slots:
		if not slot.is_empty():
			all_empty = false
	t.check(all_empty, "emptied stacks free their slot")

	t.current = "stacks"
	inv = Inventory.new(3)
	inv.add("bandage", 10)
	inv.add("bandage", 5) # Stack of 10: a second slot.
	t.eq(inv.count("bandage"), 15, "bandages across two slots")
	t.eq(inv.free_space_for("bandage"), 15, "room left: 5 in the second stack and a whole empty slot of 10")
	t.eq(inv.free_space_for("nonsense"), 0, "no room for unknown items")

	t.current = "equipment"
	inv = Inventory.new()
	t.check(not inv.equip("club_1"), "cannot equip what is not carried")
	inv.add("club_1", 1)
	t.check(inv.equip("club_1"), "equips a carried weapon")
	t.eq(inv.weapon, "club_1", "weapon slot set")
	inv.add("jacket_2", 1)
	t.check(inv.equip("jacket_2"), "equips armour")
	t.check(not inv.equip("wood_1"), "a resource cannot be equipped")
	inv.remove("club_1", 1)
	inv.unequip_missing()
	t.eq(inv.weapon, "", "equipment that left the inventory is unequipped")
	t.eq(inv.armor, "jacket_2", "other equipment stays")

	t.current = "tools"
	inv = Inventory.new()
	inv.add("axe_1", 1)
	inv.add("axe_3", 1)
	inv.add("pickaxe_2", 1)
	t.eq(inv.best_tool("axe"), "axe_3", "the highest tier axe is picked")
	t.eq(inv.best_tool("pickaxe"), "pickaxe_2", "pickaxe")
	t.eq(inv.best_tool("sickle"), "", "no such tool")

	t.current = "take everything"
	inv.add("silver", 50)
	inv.add("club_2", 1)
	inv.equip("club_2")
	var loot := inv.take_everything()
	t.eq(loot.get("silver", 0), 50, "silver is taken")
	t.eq(loot.get("axe_3", 0), 1, "tools are taken")
	t.eq(inv.count("silver"), 0, "the inventory is empty afterwards")
	t.eq(inv.weapon, "", "equipment is cleared")

	t.current = "round trip"
	inv = Inventory.new()
	inv.add("canned_food", 3)
	inv.add("plank_2", 12)
	inv.add("club_1", 1)
	inv.equip("club_1")
	var copy := Inventory.new()
	copy.load_dict(inv.to_dict())
	t.eq(copy.count("canned_food"), 3, "serialization keeps counts")
	t.eq(copy.weapon, "club_1", "serialization keeps equipment")
	copy.add("wood_1", 1)
	t.eq(inv.count("wood_1"), 0, "a copy is independent")

	t.current = "item data"
	for id in Defs.items():
		var data: Dictionary = Defs.items()[id]
		t.check(data.has("name") and data.has("kind") and int(data["stack"]) >= 1, "%s has a name, kind and stack" % id)
	for id in Defs.recipes():
		var recipe: Dictionary = Defs.recipes()[id]
		t.check(Defs.is_item(recipe["output"]), "%s produces a real item" % id)
		for input in recipe["inputs"]:
			t.check(Defs.is_item(input), "%s uses a real item %s" % [id, input])
