extends RefCounted
## Worn gear besides weapon and body armor: hood, cloak, gloves and boots. Using one equips it in its slot, every worn
## piece adds protection, the slots survive a save, forged gear is refused, and losing the items empties the slots.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "every gear slot has a craftable item family in four tiers"
	for family in [["hood", "head"], ["cloak", "cape"], ["gloves", "hands"], ["boots", "feet"]]:
		for tier in range(1, 5):
			var id: String = "%s_%d" % [family[0], tier]
			t.eq(str(Defs.item(id).get("kind", "")), family[1], "%s is worn on %s" % [id, family[1]])
			t.check(Defs.recipes().has(id), "%s can be crafted" % id)

	t.current = "using a piece equips it in its own slot on the server"
	var sim := GameServer.new(WorldGen.new(77), 77)
	var player = sim.add_player(5, "Wearer")
	for id in ["hood_2", "cloak_2", "gloves_2", "boots_2", "jacket_2"]:
		player.inventory.add(id, 1)
		sim.cmd_use(5, id)
	t.eq(player.inventory.gear, {"head": "hood_2", "cape": "cloak_2", "hands": "gloves_2", "feet": "boots_2"},
		"all four slots are filled")
	t.eq(player.inventory.armor, "jacket_2", "body armor keeps its own slot")
	t.check(player.inventory.is_equipped("boots_2") and not player.inventory.is_equipped("hood_3"), "worn pieces are known")

	t.current = "every worn piece adds protection, capped"
	var jacket_only := Inventory.new()
	jacket_only.add("jacket_2", 1)
	jacket_only.equip("jacket_2")
	t.check(Combat.apply_gear(100.0, player.inventory) < Combat.apply_gear(100.0, jacket_only),
		"a full outfit blocks more than the jacket alone")
	t.near(Combat.apply_gear(100.0, jacket_only), Combat.apply_armor(100.0, "jacket_2"), 0.0001,
		"the jacket alone protects exactly as before")
	var stacked := Inventory.new()
	for id in ["warden_jacket_3", "hood_4", "cloak_4", "gloves_4", "boots_4"]:
		stacked.add(id, 1)
		stacked.equip(id)
	t.check(Combat.apply_gear(100.0, stacked) >= 20.0 - 0.0001, "at most 80% is ever blocked")

	t.current = "worn gear survives a save and forged gear is refused"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(player.inventory.to_dict()))
	var parsed: Dictionary = SaveValidation.parse_inventory(SaveValidation.whole_numbers_as_ints(saved), Defs.INVENTORY_SLOTS)
	t.check(not parsed.is_empty(), "a real outfit loads")
	if not parsed.is_empty():
		t.eq(parsed["inventory"].gear, player.inventory.gear, "with every slot")
	var older: Dictionary = saved.duplicate(true)
	older.erase("gear")
	t.check(not SaveValidation.parse_inventory(SaveValidation.whole_numbers_as_ints(older), Defs.INVENTORY_SLOTS).is_empty(),
		"saves from before worn gear still load")
	for forged in [{"head": "boots_2"}, {"head": "hood_4"}, {"tail": "hood_2"}, {"head": 3}]:
		var bad: Dictionary = saved.duplicate(true)
		bad["gear"] = forged
		t.check(SaveValidation.parse_inventory(SaveValidation.whole_numbers_as_ints(bad), Defs.INVENTORY_SLOTS).is_empty(),
			"refused: %s" % str(forged))
	t.check(sim.valid_character_data(sim.character_data(player)), "the whole character with gear validates")

	t.current = "items that leave the bag leave their slots"
	player.inventory.remove("gloves_2", 1)
	player.inventory.unequip_missing()
	t.check(not player.inventory.gear.has("hands"), "dropped gloves are no longer worn")
	t.check(not Combat.apply_gear(100.0, player.inventory) < 0.0, "protection stays sane")
	player.inventory.take_everything()
	t.eq(player.inventory.gear, {}, "a full-loot death empties every gear slot")
