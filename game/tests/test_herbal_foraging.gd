extends RefCounted
## Foraging from real nodes must not mint medicine by replay or client input.
## Natural herbs support field crafting and server-owned healing.
const Defs = preload("res://scripts/shared/defs.gd")
const HerbalForaging = preload("res://scripts/shared/herbal_foraging.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _plant(world) -> Dictionary:
	for cx in range(-7, 8):
		for cz in range(-7, 8):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			for node in chunk["nodes"]:
				var kind: String = str(node["kind"])
				if kind not in ["bush", "berry"] or int(node["tier"]) != 1:
					continue
				var biome: String = world.biome_at(float(node["x"]), float(node["z"]))
				var zone: int = world.zone_at(float(node["x"]), float(node["z"]))
				if HerbalForaging.chance(kind, biome, zone) > 0.0:
					return node
	return {}


func _winning_seed(probability: float) -> int:
	for seed in range(1, 1024):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		# Two existing harvest draws precede the secondary herb roll:
		# base amount bonus and the foraging skill bonus.
		probe.randf()
		probe.randf()
		if probe.randf() < probability:
			return seed
	return -1


func run(t) -> void:
	t.current = "medical plants are risk-limited and never forgeable from arbitrary nodes"
	t.eq(HerbalForaging.chance("tree", "swamp", 3), 0.0,
		"cutting timber is not medicinal foraging")
	t.eq(HerbalForaging.chance("rock", "forest", 2), 0.0,
		"mining ore cannot find herbal medicine")
	t.eq(HerbalForaging.chance("bush", "plains", 2), 0.0,
		"ordinary grassland bushes have no rare herbal payload")
	t.eq(HerbalForaging.chance("berry", "beach", 3), 0.0,
		"coastal berries have no accidental medicine drops")
	t.eq(HerbalForaging.chance("bush", "forest", 0), 0.0,
		"green zones cannot mint a risky foraging reward")
	t.eq(HerbalForaging.chance("bush", "swamp", 4), 0.0,
		"unrecognized zone does not grant bonus loot")
	t.near(HerbalForaging.chance("berry", "forest", 2),
		HerbalForaging.FOREST_CHANCE, 0.00001, "forest foraging has a bounded chance")
	t.near(HerbalForaging.chance("bush", "swamp", 2),
		HerbalForaging.SWAMP_CHANCE, 0.00001, "dangerous swamp has a higher chance")
	var rng := RandomNumberGenerator.new()
	rng.seed = 312
	var state_before: int = rng.state
	t.eq(HerbalForaging.roll("tree", "swamp", 2, rng), "",
		"ineligible source cannot make herb items")
	t.eq(rng.state, state_before,
		"invalid nodes consume no global randomness")
	var herbs := 0
	for i in 100:
		var item: String = HerbalForaging.roll("berry", "swamp", 2, rng)
		t.check(item == "" or item == HerbalForaging.ITEM_ID,
			"one roll only permits one valid plant item")
		if item != "":
			herbs += 1
	t.check(herbs > 0 and herbs < 100, "deterministic chance is neither free nor impossible")

	t.current = "field remedy is inventory-paid and weaker than elite antidotes"
	t.check(Defs.is_item(HerbalForaging.ITEM_ID), "wild herbs are a real tradable stack")
	t.eq(Defs.item("herbal_poultice")["kind"], "medical",
		"poultice uses existing medical interaction and network command")
	var recipe: Dictionary = Defs.recipes()["herbal_poultice"]
	t.eq(recipe["station"], "", "poultice is field-craftable without a base")
	t.eq(recipe["inputs"][HerbalForaging.ITEM_ID], 2,
		"treatment requires two harvested herbs")
	t.eq(recipe["inputs"]["water_bottle"], 1,
		"clean water is consumed")
	t.check(float(Defs.item("herbal_poultice")["cure"]) <
		float(Defs.item("spore_antidote")["cure"]),
		"beginner medicine cannot replace costly hazard antidotes")
	var empty_bag := Inventory.new()
	t.eq(Crafting.craft(empty_bag, "herbal_poultice", false),
		Crafting.Result.MISSING_INPUTS, "no materials means no medicine")
	empty_bag.add("wild_herbs", 2)
	empty_bag.add("cloth_1", 1)
	empty_bag.add("water_bottle", 1)
	t.eq(Crafting.craft(empty_bag, "herbal_poultice", false),
		Crafting.Result.OK, "field crafting debits exact resources")
	t.eq(empty_bag.count("wild_herbs"), 0, "two source herbs spent once")
	t.eq(empty_bag.count("herbal_poultice"), 1, "one medical item produced")

	t.current = "a genuine gathering node pays only one server-authorized bonus"
	var world := WorldGen.new(417)
	var plant: Dictionary = _plant(world)
	t.check(not plant.is_empty(), "seeded world contains a real level-one forest/swamp plant")
	if plant.is_empty():
		return
	var sim := GameServer.new(world, 417)
	var survivor = sim.add_player(501, "Herbalist")
	var x: float = float(plant["x"])
	var z: float = float(plant["z"])
	survivor.position = Vector3(x, world.height_at(x, z), z)
	var chance: float = HerbalForaging.chance(str(plant["kind"]), world.biome_at(x, z),
		world.zone_at(x, z))
	var seed: int = _winning_seed(chance)
	t.check(seed >= 0, "deterministic random state can find a sample")
	if seed < 0:
		return
	var started: Dictionary = sim.cmd_gather(survivor.id, int(plant["id"]))
	t.check(bool(started.get("ok", false)),
		"server grants gathering only against a real nearby node")
	if not bool(started.get("ok", false)):
		return
	sim.rng.seed = seed
	var before: int = survivor.inventory.count(HerbalForaging.ITEM_ID)
	sim._finish_gather(survivor, plant)
	t.eq(survivor.inventory.count(HerbalForaging.ITEM_ID), before + 1,
		"completed genuine gather awards exactly one herb with fixed RNG")
	var gathered: Dictionary = {}
	for event in sim.events:
		if event.get("type") == "gathered" and int(event.get("node", -1)) == int(plant["id"]):
			gathered = event
	t.eq(int(gathered.get("herbs", 0)), 1,
		"server event announces only the actual stored herb count")
	t.eq(sim.cmd_gather(survivor.id, int(plant["id"])).get("reason", ""),
		"depleted", "replayed gather cannot roll an extra herb")
	t.eq(survivor.inventory.count(HerbalForaging.ITEM_ID), before + 1,
		"repeated requests leave herb inventory unchanged")

	t.current = "crafted remedy, health, infection and bleeding use existing RPC rules"
	t.eq(sim.cmd_use(survivor.id, "herbal_poultice").get("reason", ""),
		"not_carried", "no free medical item from use command")
	survivor.inventory.add("wild_herbs", 1) # Second rare herb collected or traded.
	survivor.inventory.add("cloth_1", 1)
	var craft: Dictionary = sim.cmd_craft(survivor.id, "herbal_poultice")
	t.check(craft.get("ok", false), "real field recipe uses owned resources")
	t.eq(survivor.inventory.count("wild_herbs"), 0, "herbs consumed in one transaction")
	t.eq(survivor.inventory.count("herbal_poultice"), 1, "medical output was created")
	var save: Dictionary = sim.character_data(survivor)
	var returned = sim.add_player(502, "Returning Herbalist", "", save)
	t.eq(returned.inventory.count("herbal_poultice"), 1,
		"tradeable crafted item survives a strict character save roundtrip")
	returned.survival.health = 70.0
	returned.survival.infection = 30.0
	returned.survival.bleeding = 12.0
	t.check(sim.cmd_use(returned.id, "herbal_poultice").get("ok", false),
		"regular medical command applies the legitimate remedy")
	t.near(returned.survival.health, 80.0, 0.0001,
		"poultice provides its bounded healing")
	t.near(returned.survival.infection, 12.0, 0.0001,
		"poultice reduces but does not erase severe infection")
	t.eq(returned.survival.bleeding, 0.0, "field dressing stops bleeding")
	t.eq(returned.inventory.count("herbal_poultice"), 0, "one used item disappears")
	t.eq(sim.cmd_use(returned.id, "herbal_poultice").get("reason", ""),
		"not_carried", "repeated use cannot reuse consumed medicine")
