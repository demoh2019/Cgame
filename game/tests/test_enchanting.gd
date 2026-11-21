extends RefCounted
## Albion-style enchantment levels, item power and the rune/soul/relic economy.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Enchanting = preload("res://scripts/shared/enchanting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "enchanted variants and item power"
	t.check(Defs.is_item("club_2@1") and Defs.is_item("club_2@3"), "gear has .1-.3 variants")
	t.check(not Defs.is_item("club_2@4"), "enchantment stops at .3")
	t.check(not Defs.is_item("wood_2@1"), "resources are not enchantable")
	t.eq(Defs.unenchanted_id("club_2@2+3"), "club_2", "unenchanted id strips enchant and quality")
	t.eq(Defs.item_power("club_4"), 700, "T4 flat is 700 IP (Albion scale)")
	t.eq(Defs.item_power("club_4@1"), 800, "each enchant adds 100 IP")
	t.eq(Defs.item_power("club_4@1+5"), 900, "Masterpiece adds 100 IP on top")
	t.check(Defs.is_item("club_4@2+3"), "enchant and quality combine")
	t.check(Combat.weapon_damage("club_2@2") > Combat.weapon_damage("club_2"), "enchanted weapons hit harder")
	t.eq(Defs.tier_of("club_2@3"), 2, "tier is unchanged")
	t.eq(Defs.enchant_cost("club_2@3"), {}, ".3 cannot go further")
	t.check(Defs.enchant_cost("club_2").has("rune"), ".1 uses runes")
	t.check(Defs.enchant_cost("club_2@1").has("soul"), ".2 uses souls")
	t.check(Defs.enchant_cost("club_2@2").has("relic"), ".3 uses relics")
	t.check(Combat.active_skill("pistol@1").get("id", "") == Combat.active_skill("pistol").get("id", ""),
		"enchanted special weapons keep their skill")

	t.current = "enchanting keeps equipment and durability"
	var bag := Inventory.new()
	bag.add("club_2", 1)
	bag.equip("club_2")
	bag.damage_item("club_2", 40.0)
	t.eq(Enchanting.enchant(bag, "club_2").get("reason"), "need_materials", "materials are required")
	var cost: Dictionary = Defs.enchant_cost("club_2")
	for id in cost:
		bag.add(str(id), int(cost[id]))
	var result: Dictionary = Enchanting.enchant(bag, "club_2")
	t.check(bool(result.get("ok", false)), "enchant succeeds with materials")
	t.eq(bag.count("club_2"), 0, "the base item is consumed")
	t.eq(bag.count("club_2@1"), 1, "the .1 variant is created")
	t.eq(bag.weapon, "club_2@1", "it stays equipped")
	t.near(bag.durability("club_2@1"), 60.0, 0.001, "durability carries over")
	t.eq(bag.count("rune"), 0, "runes are spent")
	t.eq(bag.count("silver"), 0, "silver fee is spent")

	var fine := Inventory.new()
	fine.add("club_2+4", 1)
	var fine_cost: Dictionary = Defs.enchant_cost("club_2+4")
	for id in fine_cost:
		fine.add(str(id), int(fine_cost[id]))
	t.eq(Enchanting.enchant(fine, "club_2+4").get("item"), "club_2@1+4", "enchanting keeps item quality")

	t.current = "drops scale with risk and enemy"
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var runes_safe := 0
	var runes_black := 0
	for i in 400:
		runes_safe += int(Enchanting.material_drop(0, false, false, rng).get("rune", 0))
		runes_black += int(Enchanting.material_drop(3, false, false, rng).get("rune", 0))
	t.check(runes_black > runes_safe * 2, "black zones drop far more runes")
	t.check(Enchanting.material_drop(1, true, false, rng).has("soul"), "elites always drop souls")
	t.check(Enchanting.material_drop(2, false, true, rng).has("relic"), "raid bosses drop relics")

	t.current = "server enchanting at the workbench"
	var world = WorldGen.new(4321)
	var server := GameServer.new(world, 88)
	var smith = server.add_player(702, "Enchanter")
	smith.inventory = Inventory.new()
	smith.inventory.add("club_3", 1)
	var c3: Dictionary = Defs.enchant_cost("club_3")
	for id in c3:
		smith.inventory.add(str(id), int(c3[id]))
	smith.position = Vector3(300, world.height_at(300, 300), 300)
	t.eq(server.cmd_enchant(702, "club_3").get("reason"), "no_station", "enchanting needs a workbench")
	smith.position = Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	var made: Dictionary = server.cmd_enchant(702, "club_3")
	t.eq(made.get("item"), "club_3@1", "server enchants to .1")
	t.eq(made.get("item_power"), 700, "T3.1 is 700 IP")
