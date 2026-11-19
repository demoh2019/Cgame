extends RefCounted
## Cooking outside the settlement: only real, active server campfires count.

const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")


func run(t) -> void:
	t.current = "mobile food uses a real cooking station"
	t.eq(Defs.recipes()["cooked_fish"]["station"], "campfire", "T1 fish has a field-cooking station")
	for tier in range(2, Defs.MAX_TIER + 1):
		t.eq(Defs.recipes()["cooked_fish_%d" % tier]["station"], "campfire",
			"coastal T%d fish accepts field cooking" % tier)
	var bag := Inventory.new()
	bag.add("raw_fish", 3)
	bag.add("wood_1", 4)
	t.eq(Crafting.craft(bag, "cooked_fish", false), Crafting.Result.NO_STATION,
		"carrying fish and wood does not enable cooking anywhere")
	t.eq(bag.count("raw_fish"), 3, "rejected mobile cooking leaves fish")
	t.eq(Crafting.craft(bag, "cooked_fish", false, 1, true), Crafting.Result.OK,
		"lit campfire can cook fish without hub workbench")
	t.eq(bag.count("cooked_fish"), 1, "cooked fish is real inventory food")
	t.eq(Crafting.craft(bag, "cooked_fish", true), Crafting.Result.OK,
		"existing hub workbench remains a valid cooking station")
	t.eq(Crafting.craft(bag, "plank_1", false, 1, true), Crafting.Result.NO_STATION,
		"mobile campfire cannot bypass workbench-only crafting")
	t.eq(Crafting.craft(bag, "plank_1", false), Crafting.Result.NO_STATION,
		"normal workbench restriction remains")
	t.eq(Crafting.craft(bag, "cooked_fish", true), Crafting.Result.OK,
		"remaining third fish can still be cooked at hub")
	t.eq(bag.count("cooked_fish"), 3, "both stations yield the same food")
	t.eq(Crafting.craft(bag, "cooked_fish", false, 1, true), Crafting.Result.MISSING_INPUTS,
		"active fire does not manufacture ingredients")

	t.current = "server owns field-cooking proximity, lifetime and progress"
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var place: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(place != Vector2.ZERO, "found a dry campfire construction site")
	if place == Vector2.ZERO:
		return
	var camp = sim.add_player(701, "Field Cook")
	var origin: Vector2 = place + Vector2(-2.8, 0.0)
	camp.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	camp.inventory.add("raw_fish", 3)
	camp.inventory.add("wood_1", 15)
	camp.inventory.add("stone_1", 2)
	var initial_fish: int = camp.inventory.count("raw_fish")
	t.eq(sim.cmd_craft(701, "cooked_fish")["reason"], "no_station",
		"remote fish cannot cook without fire")
	t.eq(camp.inventory.count("raw_fish"), initial_fish,
		"remote cooking rejection does not spend fish")
	var built: Dictionary = sim.cmd_light_campfire(701, place.x, place.y)
	t.check(bool(built.get("ok", false)), "real materials fund an active campfire")
	if not bool(built.get("ok", false)):
		return
	t.check(FieldCampfire.has_warmth(sim.campfires, camp.position, sim.time),
		"survivor is inside live fire radius")
	t.check(bool(sim.cmd_craft(701, "cooked_fish").get("ok", false)),
		"authoritative game server permits field cooking")
	t.eq(camp.inventory.count("raw_fish"), initial_fish - 1,
		"cooking consumes one fish and fuel")
	t.eq(camp.inventory.count("cooked_fish"), 1, "server grants one cooked meal")
	t.check(camp.dirty_inventory and camp.dirty_character, "cooking persists inventory and profession XP")

	t.current = "fish tiers still require mastery even at a fire"
	camp.inventory.add("raw_fish_2", 1)
	camp.inventory.add("wood_2", 1)
	t.eq(sim.cmd_craft(701, "cooked_fish_2")["reason"], "need_skill",
		"T2 campfire cooking cannot bypass profession progression")
	camp.progression.award_craft(1, 4)
	t.check(sim.cmd_craft(701, "cooked_fish_2")["ok"],
		"upgraded crafting skill enables T2 meals in wilderness")
	t.eq(camp.inventory.count("cooked_fish_2"), 1, "coastal tier meal is awarded")

	t.current = "expired and distant fires never grant cooking access"
	var fish_before: int = camp.inventory.count("raw_fish")
	sim.time = FieldCampfire.DURATION + 1.0
	t.eq(sim.cmd_craft(701, "cooked_fish")["reason"], "no_station",
		"expired campfire no longer acts as workbench")
	t.eq(camp.inventory.count("raw_fish"), fish_before,
		"expired fire cannot spend ingredients")
	sim.time = 0.0
	camp.position = Vector3(2000.0, world.height_at(2000.0, 0.0), 0.0)
	t.eq(sim.cmd_craft(701, "cooked_fish")["reason"], "no_station",
		"remote player cannot use somebody else's distant fire")
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	camp.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	t.check(sim.cmd_craft(701, "cooked_fish")["ok"],
		"permanent workbench remains usable after fire expires")
