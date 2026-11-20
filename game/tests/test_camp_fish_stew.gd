extends RefCounted
## A crafted prepared meal consumes clean water and fish, restores both survival
## vitals, reuses the single cooked-meal buff and cannot bypass the camp station.
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "real discoverable fish stew definition and paid campfire recipe"
	t.check(Defs.is_item(Defs.CAMP_FISH_STEW), "new meal is a registered real item")
	var item: Dictionary = Defs.item(Defs.CAMP_FISH_STEW)
	t.eq(item.get("kind"), "food", "stew uses the normal usable food inventory path")
	t.eq(item.get("tier"), 1, "starter recipe is unlocked for beginners")
	t.near(float(item.get("food", 0.0)), 40.0, 0.001, "stew restores hunger")
	t.near(float(item.get("drink", 0.0)), 38.0, 0.001, "stew hydrates a survivor")
	t.eq(HeartyMeal.tier_for_food(Defs.CAMP_FISH_STEW), 1,
		"hot stew qualifies for the existing non-stacking T1 cooked meal")
	var recipe: Dictionary = Defs.recipes().get(Defs.CAMP_FISH_STEW, {})
	t.check(not recipe.is_empty(), "stew appears among live crafting recipes")
	t.eq(recipe.get("station"), "campfire", "requires real fire or hub workbench")
	t.eq(recipe.get("inputs"), {"raw_fish": 1, "water_bottle": 1, "wood_1": 1},
		"raw lake water cannot be used as clean drinking water")
	var bag := Inventory.new()
	bag.add("raw_fish", 1)
	bag.add("wood_1", 1)
	t.eq(Crafting.craft(bag, Defs.CAMP_FISH_STEW, false, 1, true),
		Crafting.Result.MISSING_INPUTS, "fish and fire cannot invent clean water")
	t.eq(bag.count("raw_fish"), 1, "refused meal does not use fish")
	bag.add("murky_water", 1)
	t.eq(Crafting.craft(bag, Defs.CAMP_FISH_STEW, false, 1, true),
		Crafting.Result.MISSING_INPUTS, "murky water does not count as clean water")
	bag.add("water_bottle", 1)
	var before: Dictionary = bag.to_dict()
	t.eq(Crafting.craft(bag, Defs.CAMP_FISH_STEW, false),
		Crafting.Result.NO_STATION, "firewood alone does not count as a campfire")
	t.eq(bag.to_dict(), before, "station denial does not spend any ingredients")
	t.eq(Crafting.craft(bag, Defs.CAMP_FISH_STEW, false, 1, true),
		Crafting.Result.OK, "lit campfire permits legitimate stew cooking")
	t.eq(bag.count(Defs.CAMP_FISH_STEW), 1, "one prepared meal is created")
	t.eq(bag.count("raw_fish"), 0, "fish spent exactly once")
	t.eq(bag.count("water_bottle"), 0, "clean water spent exactly once")
	t.eq(bag.count("wood_1"), 0, "wood spent exactly once")

	t.current = "atomic full-backpack denial and emptied input slots"
	var full := Inventory.new(3)
	full.add("raw_fish", 2)
	full.add("water_bottle", 2)
	full.add("wood_1", 2)
	before = full.to_dict()
	t.eq(Crafting.craft(full, Defs.CAMP_FISH_STEW, false, 1, true),
		Crafting.Result.NO_SPACE, "a packed backpack cannot create an extra stack")
	t.eq(full.to_dict(), before, "failed craft rolls back all three consumed inputs")
	var freed := Inventory.new(3)
	freed.add("raw_fish", 1)
	freed.add("water_bottle", 1)
	freed.add("wood_1", 1)
	t.eq(Crafting.craft(freed, Defs.CAMP_FISH_STEW, false, 1, true),
		Crafting.Result.OK, "spending entire stacks frees output capacity")
	t.eq(freed.count(Defs.CAMP_FISH_STEW), 1,
		"crafted stew occupies the released slot without loss")
	t.eq(Crafting.craft(freed, Defs.CAMP_FISH_STEW, false, 1, true),
		Crafting.Result.MISSING_INPUTS, "replayed crafting cannot mint more food")

	t.current = "authoritative world fire, inventory and dual survival recovery"
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var place: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(place != Vector2.ZERO, "deterministic open campsite found")
	if place == Vector2.ZERO:
		return
	var survivor = sim.add_player(921, "Stew Cook")
	var origin := place + Vector2(-2.8, 0.0)
	survivor.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	survivor.inventory.add("raw_fish", 2)
	survivor.inventory.add("water_bottle", 2)
	survivor.inventory.add("wood_1", 10)
	survivor.inventory.add("stone_1", 2)
	var fish_before: int = survivor.inventory.count("raw_fish")
	t.eq(sim.cmd_craft(921, Defs.CAMP_FISH_STEW).get("reason", ""), "no_station",
		"server denies wilderness cooking without a live fire")
	t.eq(survivor.inventory.count("raw_fish"), fish_before,
		"denied remote craft spends nothing")
	var fire: Dictionary = sim.cmd_light_campfire(921, place.x, place.y)
	t.check(bool(fire.get("ok", false)), "server creates a true material-paid fire")
	if not bool(fire.get("ok", false)):
		return
	var cooked: Dictionary = sim.cmd_craft(921, Defs.CAMP_FISH_STEW)
	t.check(bool(cooked.get("ok", false)), "real server can cook stew at a real fire")
	if not bool(cooked.get("ok", false)):
		return
	t.eq(survivor.inventory.count("raw_fish"), fish_before - 1,
		"server debited exactly one fish")
	t.eq(survivor.inventory.count(Defs.CAMP_FISH_STEW), 1,
		"server awarded one normal carried meal")
	survivor.survival.hunger = 20.0
	survivor.survival.thirst = 20.0
	var food_power: float = 1.0 + survivor.skills.bonus("food_power")
	var used: Dictionary = sim.cmd_use(921, Defs.CAMP_FISH_STEW)
	t.check(bool(used.get("ok", false)), "food consumed via existing authoritative use command")
	t.eq(survivor.inventory.count(Defs.CAMP_FISH_STEW), 0,
		"one click consumes exactly one stew")
	t.near(survivor.survival.hunger, minf(100.0, 20.0 + 40.0 * food_power),
		0.001, "server restores the meal's hunger")
	t.near(survivor.survival.thirst, minf(100.0, 20.0 + 38.0 * food_power),
		0.001, "server restores thirst with no free extra water item")
	t.eq(survivor.meal_tier, 1, "normal cooked food buff applies without custom state")
	t.near(survivor.meal_seconds, HeartyMeal.duration(1), 0.001,
		"stew grants the existing bounded T1 meal timer")
	t.check(survivor.dirty_inventory and survivor.dirty_character,
		"stew use marks character and inventory for persistence")
	t.eq(sim.cmd_use(921, Defs.CAMP_FISH_STEW).get("reason", ""), "not_carried",
		"second use cannot mint hydration or a meal buff")
	t.check(sim.valid_character_data(sim.character_data(survivor)),
		"existing save schema accepts the stew and meal timer")

	t.current = "ordinary food stays non-hydrating, distant or expired fire is rejected"
	survivor.survival.thirst = 17.0
	survivor.inventory.add("canned_food", 1)
	t.check(sim.cmd_use(921, "canned_food").get("ok", false),
		"ordinary canned rations still work")
	t.near(survivor.survival.thirst, 17.0, 0.001,
		"other food cannot grant unintended hydration")
	var second_fish: int = survivor.inventory.count("raw_fish")
	sim.time = float(sim.campfires[int(fire["id"])]["expires"]) + 1.0
	t.eq(sim.cmd_craft(921, Defs.CAMP_FISH_STEW).get("reason", ""), "no_station",
		"expired fire no longer cooks the meal")
	t.eq(survivor.inventory.count("raw_fish"), second_fish,
		"failed expired-fire craft conserves real ingredients")
	sim.time = 0.0
	survivor.position = Vector3(2000.0, world.height_at(2000.0, 0.0), 0.0)
	t.eq(sim.cmd_craft(921, Defs.CAMP_FISH_STEW).get("reason", ""), "no_station",
		"remote survivor cannot exploit a distant fire")
	t.eq(sim.cmd_use(999, Defs.CAMP_FISH_STEW).get("reason", ""), "dead",
		"unknown peer cannot consume stew")
	var net := Net.new()
	t.check(net.has_method("c_craft") and net.has_method("c_use"),
		"multiplayer crafting and use RPCs already connect the new item")
	net.free()
