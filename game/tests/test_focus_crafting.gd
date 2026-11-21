extends RefCounted
## Albion-style focus: a daily budget that returns materials when crafting in a city.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const ReturnRate = preload("res://scripts/shared/return_rate.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "focus maths"
	t.check(ReturnRate.focus_cost("plank_3", 3, 1) < ReturnRate.focus_cost("club_3", 3, 1), "refining costs less focus")
	t.check(ReturnRate.focus_cost("club_4", 4, 1) > ReturnRate.focus_cost("club_1", 1, 1), "higher tiers cost more")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var total := 0
	for i in 1000:
		total += int(ReturnRate.returned({"wood_1": 2}, ReturnRate.FOCUS_RATE, rng).get("wood_1", 0))
	t.near(float(total) / 1000.0, 0.7, 0.06, "35% of materials come back on average")
	t.eq(ReturnRate.returned({"wood_1": 10}, 0.0, rng), {}, "no focus, nothing back")

	t.current = "focus persists"
	var p := Progression.new()
	p.focus = 1234.0
	var restored := Progression.new()
	t.check(restored.load_dict(p.to_dict()), "save loads")
	t.near(restored.focus, 1234.0, 0.001, "focus restored")

	t.current = "server focus crafting"
	var world = WorldGen.new(2468)
	var server := GameServer.new(world, 5)
	var crafter = server.add_player(901, "Crafter")
	crafter.inventory = Inventory.new()
	crafter.inventory.add("wood_1", 40)
	crafter.position = Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	var plain: Dictionary = server.cmd_craft(901, "plank_1", 5)
	t.check(bool(plain.get("ok", false)), "ordinary craft works")
	t.eq(crafter.inventory.count("wood_1"), 30, "ordinary craft returns nothing")
	var before_focus: float = crafter.progression.focus
	var focused: Dictionary = server.cmd_craft(901, "plank_1", 10, false, true)
	t.check(bool(focused.get("ok", false)), "focus craft works at the hub")
	t.check(crafter.inventory.count("wood_1") > 10, "focus returns some wood")
	t.check(crafter.progression.focus < before_focus, "focus is spent")
	crafter.progression.focus = 0.0
	t.eq(server.cmd_craft(901, "plank_1", 1, false, true).get("reason"), "need_focus", "no focus left")
	crafter.position = Vector3(400, world.height_at(400, 400), 400)
	t.eq(server.cmd_craft(901, "plank_1", 1, false, true).get("reason"), "focus_needs_city", "focus only in a city")
