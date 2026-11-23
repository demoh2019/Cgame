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

	t.current = "save recovery never creates item stacks or phantom equipment"
	var guarded := Inventory.new(3)
	guarded.add("bandage", 1)
	guarded.load_dict({"slots": [
		{"id": "wood_1", "count": 999999999999.0},
		{"id": "club_1", "count": 1.0},
		{"id": "silver", "count": -4},
		{"id": "jacket_2", "count": 1}],
		"weapon": "jacket_2", "armor": "club_1",
		"gear": {"head": "club_1", "feet": "jacket_2"},
		"wear": {"club_1": 45.0, "jacket_2": 10.0,
			"silver": 0.0, "bogus": 12.0}})
	t.eq(guarded.slots.size(), 3, "loaded data cannot expand backpack capacity")
	t.eq(guarded.count("wood_1"), Defs.stack_size("wood_1"),
		"corrupt oversized stack is bounded by the item catalog")
	t.eq(guarded.count("club_1"), 1, "integral JSON float count remains compatible")
	t.eq(guarded.count("silver"), 0, "negative stacks are discarded")
	t.eq(guarded.count("jacket_2"), 0, "extra saved slots are discarded")
	t.eq(guarded.count("bandage"), 0, "loading replaces rather than appends items")
	t.eq(guarded.weapon, "", "wrong-kind saved weapon is cleared")
	t.eq(guarded.armor, "", "unowned saved armor is cleared")
	t.eq(guarded.gear, {}, "invalid gear slots are cleared")
	t.near(guarded.durability("club_1"), 45.0, 0.0001,
		"valid owned gear durability survives recovery")
	t.eq(guarded.wear.size(), 1, "stale durability of absent items is dropped")
	guarded.load_dict({"slots": ["not_a_slot", {"id": "wood_1", "count": NAN},
		{"id": "wood_1", "count": 2.5}]})
	t.eq(guarded.count("wood_1"), 0,
		"malformed fields and fractional or nonfinite quantities are discarded")
	t.eq(guarded.slots.size(), 3, "malformed saves keep the original capacity")
	guarded.load_dict({"slots": [{"id": "club_1", "count": 1},
		{"id": "jacket_2", "count": 1}], "weapon": "club_1",
		"armor": "jacket_2", "wear": {"jacket_2": NAN}})
	t.eq(guarded.weapon, "club_1", "legitimate saved weapon remains equipped")
	t.eq(guarded.armor, "jacket_2", "legitimate saved armor remains equipped")
	t.eq(guarded.durability("jacket_2"), 100.0,
		"nonfinite saved wear safely restores pristine durability")

	t.current = "item data"
	for id in Defs.items():
		var data: Dictionary = Defs.items()[id]
		t.check(data.has("name") and data.has("kind") and int(data["stack"]) >= 1, "%s has a name, kind and stack" % id)
	for id in Defs.recipes():
		var recipe: Dictionary = Defs.recipes()[id]
		t.check(Defs.is_item(recipe["output"]), "%s produces a real item" % id)
		for input in recipe["inputs"]:
			t.check(Defs.is_item(input), "%s uses a real item %s" % [id, input])
