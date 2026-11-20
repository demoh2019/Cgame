extends RefCounted
## Auto provisioning selects only legitimate food/drink from real carried gear.
const Defs = preload("res://scripts/shared/defs.gd")
const Provisions = preload("res://scripts/shared/smart_provisions.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	var sim := Server.new(WorldGen.new(4862), 4862)
	var p = sim.add_player(771, "Quartermaster")
	p.inventory.remove("canned_food", p.inventory.count("canned_food"))
	p.inventory.remove("water_bottle", p.inventory.count("water_bottle"))
	t.current = "safe smart provisions: no free items or invalid commands"
	t.eq(sim.cmd_smart_provision(555, "food").get("reason", ""), "dead",
		"unknown peer cannot spend another player's supplies")
	t.eq(sim.cmd_smart_provision(771, "gear").get("reason", ""), "invalid_intent",
		"client cannot select equipment or arbitrary inventory items")
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "no_provision",
		"full survivor cannot automatically waste food")
	p.survival.hunger = 30.0
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "no_provision",
		"starving player with no food cannot create items")
	p.inventory.add("raw_fish", 1)
	p.inventory.add("murky_water", 1)
	t.eq(Provisions.pick(p.inventory, p.survival, "food"), "",
		"raw fish with poisoning risk never enters automated selection")
	p.survival.thirst = 10.0
	t.eq(Provisions.pick(p.inventory, p.survival, "drink"), "",
		"unboiled lake water never enters automated selection")
	t.eq(p.inventory.count("raw_fish"), 1, "unsafe supplies remain untouched")

	t.current = "food selection minimizes waste without inventing bonus meals"
	p.survival.thirst = 100.0
	p.survival.hunger = 82.0
	p.inventory.add("berries", 2)
	p.inventory.add("canned_food", 2)
	var first: Dictionary = sim.cmd_smart_provision(771, "food")
	t.check(bool(first.get("ok", false)), "smart rations successfully consume real food")
	t.eq(first.get("item", ""), "berries", "small hunger gap chooses small ration")
	t.near(p.survival.hunger, 94.0, 0.001, "real berries restore 12 hunger")
	t.eq(p.inventory.count("berries"), 1, "one berries item spent")
	t.eq(p.inventory.count("canned_food"), 2, "cans preserved")
	p.survival.hunger = 50.0
	var second: Dictionary = sim.cmd_smart_provision(771, "food")
	t.eq(second.get("item", ""), "canned_food", "large hunger gap uses full ration")
	t.near(p.survival.hunger, 92.0, 0.001, "existing food rules restore 42 hunger")
	t.eq(p.inventory.count("canned_food"), 1, "one canned food item spent")

	t.current = "hydration reserves stew unless both hunger and thirst are low"
	p.survival.hunger = 100.0
	p.survival.thirst = 40.0
	p.inventory.add("water_bottle", 2)
	p.inventory.add(Defs.CAMP_FISH_STEW, 1)
	var drink_only: Dictionary = sim.cmd_smart_provision(771, "drink")
	t.eq(drink_only.get("item", ""), "water_bottle",
		"clean bottle preferred when survivor is not hungry")
	t.eq(p.inventory.count(Defs.CAMP_FISH_STEW), 1,
		"valuable dual-purpose meal preserved for later")
	t.near(p.survival.thirst, 85.0, 0.001, "drink uses normal hydration")
	p.survival.hunger = 40.0
	p.survival.thirst = 40.0
	var stew: Dictionary = sim.cmd_smart_provision(771, "drink")
	t.eq(stew.get("item", ""), Defs.CAMP_FISH_STEW,
		"hungry and thirsty survivor uses combined soup")
	t.near(p.survival.hunger, 80.0, 0.001, "stew provides real food")
	t.near(p.survival.thirst, 78.0, 0.001, "stew provides real water")
	t.eq(p.inventory.count(Defs.CAMP_FISH_STEW), 0, "one cooked meal spent")
	t.eq(p.inventory.count("water_bottle"), 1, "remaining bottle stays carried")
	t.eq(p.inventory.count("murky_water"), 1, "murky water remains unsafe")

	t.current = "request validation and existing normal item restrictions"
	p.survival.hunger = 92.0
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "no_provision",
		"less than 15 hunger missing spends nothing")
	p.survival.hunger = 25.0
	p.mounted = true
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "mounted",
		"mounted survivors cannot bypass food-use rules")
	t.eq(p.inventory.count("canned_food"), 1, "denied mounted use preserves rations")
	p.mounted = false
	p.recall = {"channel": true}
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "recall_channeling",
		"recall cannot be bypassed by smart ration hotkey")
	p.recall.clear()
	p.survival.hunger = NAN
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "no_provision",
		"corrupt non-finite survival stats cannot consume items")
	p.survival.hunger = 25.0
	p.survival.hurt(1000.0)
	t.eq(sim.cmd_smart_provision(771, "food").get("reason", ""), "dead",
		"dead character cannot eat through shortcut")
	var net := Net.new()
	t.check(net.has_method("c_smart_provision"),
		"authenticated smart provisioning RPC exists")
	net.free()
