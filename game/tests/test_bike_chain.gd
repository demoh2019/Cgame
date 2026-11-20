extends RefCounted
## Verify craft cost, server movement, infected hearing, persistence and anti-cheat.

const Defs = preload("res://scripts/shared/defs.gd")
const BikeChain = preload("res://scripts/shared/bike_chain.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "chain wrap is crafted and paid"
	t.eq(Defs.item(BikeChain.ITEM_ID).get("kind"), "bike_wrap", "item registered")
	t.eq(Defs.recipes()[BikeChain.ITEM_ID]["station"], "workbench", "station required")
	var bag := Inventory.new()
	bag.add("cloth_1", 2)
	bag.add("fiber_1", 2)
	bag.add("scrap", 2)
	t.eq(Crafting.craft(bag, BikeChain.ITEM_ID, false), Crafting.Result.NO_STATION,
		"no free field crafting")
	t.eq(Crafting.craft(bag, BikeChain.ITEM_ID, true), Crafting.Result.OK,
		"workbench produces one chain wrap")
	t.eq(bag.count(BikeChain.ITEM_ID), 1, "item is physically in backpack")
	t.eq(BikeChain.apply_reason(bag, 0.0), "missing_bike", "must own bike")
	bag.add(Mounts.ITEM_ID, 1)
	t.eq(BikeChain.apply_reason(bag, 0.0), "", "legitimate owner can apply")
	t.eq(BikeChain.apply_reason(bag, 12.0), "already_wrapped", "no buff stacking")
	t.eq(BikeChain.apply_reason(bag, NAN), "invalid_state", "invalid duration rejected")
	t.eq(BikeChain.riding_radius(0.0), BikeChain.RIDING_NOISE_RADIUS, "normal bike rattles")
	t.eq(BikeChain.riding_radius(12.0), BikeChain.WRAPPED_NOISE_RADIUS, "wrap lowers noise")
	t.eq(BikeChain.riding_radius(INF), BikeChain.RIDING_NOISE_RADIUS,
		"nonfinite timer does not silence bike")

	t.current = "authoritative use and input"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var rider = sim.add_player(91, "Rider")
	rider.inventory.add(BikeChain.ITEM_ID, 2)
	t.eq(sim.cmd_use(91, BikeChain.ITEM_ID)["reason"], "missing_bike",
		"cannot use kit with no bicycle")
	t.eq(rider.inventory.count(BikeChain.ITEM_ID), 2, "failed use spends nothing")
	rider.inventory.add(Mounts.ITEM_ID, 1)
	var used: Dictionary = sim.cmd_use(91, BikeChain.ITEM_ID)
	t.check(bool(used.get("ok", false)), "kit activated by real server inventory")
	t.eq(rider.inventory.count(BikeChain.ITEM_ID), 1, "one kit debited")
	t.eq(sim.cmd_use(91, BikeChain.ITEM_ID)["reason"], "already_wrapped",
		"second use does not extend effect")
	t.eq(rider.inventory.count(BikeChain.ITEM_ID), 1, "no repeated consumption")
	t.check(rider.dirty_inventory and rider.dirty_character, "change scheduled for save")
	t.near(float(sim.snapshot_for(91)["you"]["chain_wrap_seconds"]),
		BikeChain.DURATION_SECONDS, 0.001, "HUD sees server timer")
	t.check(bool(sim.cmd_toggle_mount(91).get("mounted", false)),
		"owner can ride wrapped bicycle")
	t.eq(sim.cmd_use(91, BikeChain.ITEM_ID)["reason"], "mounted",
		"cannot modify kit while riding")
	rider.input_budget = 0.25
	sim.submit_input(91, 1, 0.0, 0.0, false, 0.0, 0.05)
	t.near(rider.noise_radius, 0.0, 0.001, "idle bike creates no sound")
	sim.submit_input(91, 2, 1.0, 0.0, false, 0.0, 0.05)
	t.near(rider.noise_radius, BikeChain.WRAPPED_NOISE_RADIUS, 0.001,
		"validated movement uses reduced radius")
	t.check(rider.noise_timer >= BikeChain.SOUND_SECONDS, "AI hears active sound")
	var first: float = rider.noise_radius
	sim.submit_input(91, 2, 1.0, 0.0, false, 0.0, 0.05)
	t.near(rider.noise_radius, first, 0.001, "replayed input cannot raise sound")
	sim._tick_players(BikeChain.SOUND_SECONDS + 0.1)
	t.near(rider.noise_radius, 0.0, 0.001, "moving sound decays after stopping")
	t.check(rider.chain_wrap_seconds < BikeChain.DURATION_SECONDS,
		"server tick reduces temporary effect")

	t.current = "save validation and relog"
	var saved: Dictionary = sim.character_data(rider)
	t.check(saved.has("chain_wrap_seconds") and not saved.has("noise_radius"),
		"only wrap duration saved, never raw noise")
	var rejoined = sim.add_player(92, "Returned", "", saved)
	t.eq(rejoined.mounted, false, "relogin never creates mounted state")
	t.near(rejoined.chain_wrap_seconds, rider.chain_wrap_seconds, 0.001,
		"relogin retains remaining duration")
	for bad in [-1.0, NAN, INF, BikeChain.DURATION_SECONDS + 1.0, "12"]:
		var corrupted: Dictionary = saved.duplicate(true)
		corrupted["chain_wrap_seconds"] = bad
		t.check(not sim.apply_character(rejoined, corrupted), "invalid save refused")
		t.near(rejoined.chain_wrap_seconds, rider.chain_wrap_seconds, 0.001,
			"failed load leaves state unchanged")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("chain_wrap_seconds")
	t.check(sim.apply_character(rejoined, legacy), "old save remains valid")
	t.eq(rejoined.chain_wrap_seconds, 0.0, "legacy character has no free wrap")

	t.current = "ordinary moving bike attracts nearby infected"
	var loud := GameServer.new(world, 47)
	var courier = loud.add_player(93, "Courier")
	courier.inventory.add(Mounts.ITEM_ID, 1)
	t.check(bool(loud.cmd_toggle_mount(93).get("ok", false)), "bike mounts normally")
	courier.position = Vector3(310.0, world.height_at(310.0, 310.0), 310.0)
	courier.input_budget = 0.25
	loud.submit_input(93, 1, 1.0, 0.0, false, 0.0, 0.05)
	t.near(courier.noise_radius, BikeChain.RIDING_NOISE_RADIUS, 0.001,
		"moving bike is loud to nearby infected")
	var infected = Zombie.new(loud.new_id(), "walker",
		Vector3(335.0, world.height_at(335.0, 310.0), 310.0))
	loud.zombies[infected.id] = infected
	loud._tick_zombies(0.05)
	t.eq(infected.target_id, 93, "infected hears bike beyond sight distance")
	loud._tick_players(BikeChain.SOUND_SECONDS + 0.1)
	t.eq(courier.noise_radius, 0.0, "stopped bike eventually quiets")
