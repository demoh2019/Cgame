extends RefCounted
## An actual shoreline -> unboiled water -> lit campfire -> drinkable water loop.
## All inventory movement, cooldown and station checks are server authoritative.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const FieldWater = preload("res://scripts/shared/field_water.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _shore(world) -> Vector3:
	for x in range(-260, 261, 4):
		for z in range(-260, 261, 4):
			var point := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if FieldWater.can_access_lake(world, point):
				return point
	return Vector3.INF


func run(t) -> void:
	t.current = "water pouch and boiled water are catalog items and real crafting recipes"
	t.eq(Defs.item("empty_water_pouch").get("kind", ""), "water_pouch",
		"pouch is not a drink and can only be filled by the game server")
	t.eq(Defs.item("murky_water").get("kind", ""), "raw_water",
		"untreated lake water cannot be consumed as a safe drink")
	t.eq(Defs.recipes()["empty_water_pouch"]["inputs"],
		{"cloth_1": 1, "fiber_1": 1}, "a pouch costs field-gathered material")
	t.eq(Defs.recipes()["boiled_water"]["station"], "campfire",
		"boiling requires an active fire or real settlement workbench")
	t.eq(Defs.recipes()["boiled_water"]["output"], "water_bottle",
		"the result is the existing ordinary drinkable water")
	t.eq(Defs.recipes()["boiled_water"]["inputs"],
		{"murky_water": 1, "wood_1": 1}, "boiling spends dirty water and fuel")

	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var p = sim.add_player(1908, "Water Carrier")
	t.eq(sim.cmd_use(9999, "empty_water_pouch").get("reason", ""), "dead",
		"unknown peers cannot collect water")
	t.eq(sim.cmd_use(p.id, "empty_water_pouch").get("reason", ""), "not_carried",
		"players cannot fill an imaginary pouch")
	p.inventory.add("cloth_1", 1)
	t.eq(sim.cmd_craft(p.id, "empty_water_pouch").get("reason", ""),
		"missing_inputs", "missing fiber cannot produce equipment")
	p.inventory.add("fiber_1", 1)
	t.check(sim.cmd_craft(p.id, "empty_water_pouch").get("ok", false),
		"a real craft produces one empty pouch")
	t.eq(p.inventory.count("empty_water_pouch"), 1, "a real pouch enters the bag")
	t.eq(sim.cmd_use(p.id, "empty_water_pouch").get("reason", ""), "no_water",
		"town does not permit remote lake collection")

	t.current = "real shoreline collection with one shared persisted cooldown"
	var shore: Vector3 = _shore(world)
	t.check(shore.is_finite(), "the deterministic world has a reachable shore")
	if not shore.is_finite():
		return
	p.position = shore
	var collected: Dictionary = sim.cmd_use(p.id, "empty_water_pouch")
	t.check(collected.get("ok", false), "pouch collects water at a real shoreline")
	t.eq(collected.get("item", ""), "murky_water", "only unsafe lake water is produced")
	t.eq(p.inventory.count("empty_water_pouch"), 0, "exactly one pouch was consumed")
	t.eq(p.inventory.count("murky_water"), 1, "one dirty-water item is stored")
	t.eq(p.lake_drink_cooldown, FieldWater.COOLDOWN_SECONDS,
		"collection starts the pre-existing persistent lake timer")
	t.check(p.dirty_inventory and p.dirty_character,
		"item and cooldown are marked for saving")
	p.inventory.add("empty_water_pouch", 1)
	t.eq(sim.cmd_use(p.id, "empty_water_pouch").get("reason", ""), "cooldown",
		"immediate replay does not fill a second pouch")
	t.eq(sim.cmd_refill_canteen(p.id).get("reason", ""), "cooldown",
		"the filter route cannot skip the water collection timer")
	p.survival.thirst = 20.0
	t.eq(sim.cmd_drink_water(p.id).get("reason", ""), "cooldown",
		"direct lake drinking cannot skip the collection timer")
	t.eq(sim.cmd_use(p.id, "murky_water").get("reason", ""), "not_usable",
		"raw water does not apply health or thirst effects")
	t.eq(p.survival.thirst, 20.0, "rejected unsafe drink grants no hydration")
	t.eq(p.inventory.count("murky_water"), 1,
		"rejected unsafe drink preserves the dirty-water item")
	var saved: Dictionary = sim.character_data(p)
	t.eq(saved["lake_drink_cooldown"], FieldWater.COOLDOWN_SECONDS,
		"the original save schema persists collection cooldown")
	p.lake_drink_cooldown = 0.0
	t.check(sim.apply_character(p, saved), "save restores water-gathering state")
	t.eq(p.lake_drink_cooldown, FieldWater.COOLDOWN_SECONDS,
		"rejoining does not reset the cooldown")

	t.current = "boiling requires a lit fire, consumes fuel and yields a safe drink"
	p.inventory.add("wood_1", 1)
	t.eq(sim.cmd_craft(p.id, "boiled_water").get("reason", ""), "no_station",
		"remote wilderness crafting cannot boil water at a cold spot")
	t.eq(p.inventory.count("murky_water"), 1, "cold crafting does not waste water")
	var clean_before: int = p.inventory.count("water_bottle")
	sim.campfires[991] = {"id": 991, "x": shore.x, "y": shore.y, "z": shore.z,
		"expires": sim.time + 60.0}
	t.check(sim.cmd_craft(p.id, "boiled_water").get("ok", false),
		"server accepts the recipe while an active fire is actually nearby")
	t.eq(p.inventory.count("murky_water"), 0, "boiling consumes unboiled water")
	t.eq(p.inventory.count("wood_1"), 0, "boiling consumes one fuel wood")
	t.eq(p.inventory.count("water_bottle"), clean_before + 1,
		"one additional standard water bottle is produced")
	p.survival.infection = 0.0
	t.check(sim.cmd_use(p.id, "water_bottle").get("ok", false),
		"boiled water can be used through the existing drink action")
	t.near(p.survival.thirst, 65.0, 0.0001, "safe water hydrates normally")
	t.eq(p.survival.infection, 0.0, "boiled water does not add lake infection")
	sim.campfires.clear()
	t.eq(sim.cmd_craft(p.id, "boiled_water").get("reason", ""), "no_station",
		"an expired or absent campfire cannot be used for boiling")

	t.current = "water pouch swap is atomic when the backpack is full"
	p.lake_drink_cooldown = 0.0
	p.inventory = Inventory.new(2)
	p.inventory.add("empty_water_pouch", 2)
	p.inventory.add("water_bottle", 10)
	var packed: Dictionary = p.inventory.to_dict()
	t.eq(sim.cmd_use(p.id, "empty_water_pouch").get("reason", ""), "no_space",
		"full bag with two pouches cannot receive a third item type")
	t.eq(p.inventory.to_dict(), packed, "failed swap restores every stack")
	t.eq(p.lake_drink_cooldown, 0.0, "failed swap does not start the timer")
	p.inventory = Inventory.new(2)
	p.inventory.add("empty_water_pouch", 1)
	p.inventory.add("water_bottle", 10)
	t.check(sim.cmd_use(p.id, "empty_water_pouch").get("ok", false),
		"consuming the last pouch frees space for the collected water")
	t.eq(p.inventory.count("murky_water"), 1,
		"freed slot holds exactly one unit of dirty water")
	t.eq(p.inventory.count("water_bottle"), 10,
		"other drink stacks remain intact")
