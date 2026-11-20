extends RefCounted
## Bike chain maintenance: item-paid, server-owned, loss/expiry/save secure.

const BikeService = preload("res://scripts/shared/bike_service.gd")
const BikeChain = preload("res://scripts/shared/bike_chain.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func run(t) -> void:
	t.current = "repair supplies and wear rules"
	t.eq(Defs.item(BikeService.ITEM_ID).get("kind"), "bike_service",
		"service kit is a real material item")
	t.eq(Defs.recipes()[BikeService.ITEM_ID]["station"], "workbench",
		"service kit requires workbench resources")
	t.near(BikeService.wear_for_distance("plains", 10.0), 10.0, 0.001,
		"firm ground consumes distance one to one")
	t.near(BikeService.wear_for_distance("swamp", 10.0), 20.0, 0.001,
		"mud accelerates chain wear")
	t.near(BikeService.wear_for_distance("beach", 10.0), 16.0, 0.001,
		"sand accelerates chain wear")
	t.near(BikeService.wear_for_distance("forest", 10.0), 13.0, 0.001,
		"roots accelerate chain wear")
	t.eq(BikeService.wear_for_distance("swamp", NAN), 0.0,
		"nonfinite motion cannot consume arbitrary distance")
	t.eq(BikeService.wear_for_distance("swamp", -10.0), 0.0,
		"backwards forged distance cannot repair chain")
	t.near(BikeService.remaining_after_move(5.0, "swamp", 10.0), 0.0, 0.001,
		"service wears out without becoming negative")
	t.eq(BikeService.riding_noise_radius(100.0, BikeChain.RIDING_NOISE_RADIUS),
		BikeService.SERVICED_NOISE_RADIUS, "serviced bike is quieter than normal")
	t.eq(BikeService.riding_noise_radius(100.0, BikeChain.WRAPPED_NOISE_RADIUS),
		BikeChain.WRAPPED_NOISE_RADIUS, "existing quiet wrap is still best")
	t.eq(BikeService.riding_noise_radius(0.0, BikeChain.RIDING_NOISE_RADIUS),
		BikeChain.RIDING_NOISE_RADIUS, "worn drive returns to original bike sound")

	t.current = "server purchase and anti-spam"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world)
	var rider = sim.add_player(312, "Mechanic")
	t.eq(sim.cmd_use(312, BikeService.ITEM_ID).get("reason"), "not_carried",
		"cannot service using nonexistent items")
	rider.inventory.add(BikeService.ITEM_ID, 2)
	t.eq(sim.cmd_use(312, BikeService.ITEM_ID).get("reason"), "missing_bike",
		"cannot service a fictional mount")
	t.eq(rider.inventory.count(BikeService.ITEM_ID), 2,
		"failed service never spends resources")
	rider.inventory.add(Mounts.ITEM_ID, 1)
	var repaired: Dictionary = sim.cmd_use(312, BikeService.ITEM_ID)
	t.check(bool(repaired.get("ok", false)), "paid service succeeds when carrying bike")
	t.near(rider.bike_service_meters, BikeService.MAX_METERS, 0.001,
		"one repair kit grants the limited service distance")
	t.eq(rider.inventory.count(BikeService.ITEM_ID), 1,
		"exactly one physical kit is spent")
	t.eq(sim.cmd_use(312, BikeService.ITEM_ID).get("reason"), "already_serviced",
		"cannot stack repairs or consume spare kits")
	t.eq(rider.inventory.count(BikeService.ITEM_ID), 1,
		"duplicate repair does not consume kit")
	t.near(float(sim.snapshot_for(312)["you"]["bike_service_meters"]),
		BikeService.MAX_METERS, 0.001, "HUD receives server-owned service state")
	t.check(bool(sim.cmd_toggle_mount(312).get("mounted", false)),
		"serviced bike mounts normally")
	t.eq(sim.cmd_use(312, BikeService.ITEM_ID).get("reason"), "mounted",
		"must dismount before servicing again")

	t.current = "real server movement wears serviced chain"
	var origin: Vector3 = rider.position
	rider.input_budget = 0.1
	sim.submit_input(312, 1, 1.0, 0.0, false, 0.0, 0.1)
	var moved: float = Vector2(rider.position.x - origin.x,
		rider.position.z - origin.z).length()
	t.check(moved > 0.01, "bike travels on normal world surface")
	var expected: float = BikeService.remaining_after_move(
		BikeService.MAX_METERS, world.biome_at(origin.x, origin.z), moved)
	t.near(rider.bike_service_meters, expected, 0.001,
		"only observed displacement, never client distance, consumes service")
	t.eq(rider.noise_radius, BikeService.SERVICED_NOISE_RADIUS,
		"server AI hears actual quiet riding distance")
	var unchanged: float = rider.bike_service_meters
	sim.submit_input(312, 2, 0.0, 0.0, false, 0.0, 0.1)
	t.near(rider.bike_service_meters, unchanged, 0.001,
		"idle input cannot consume service")
	t.check(bool(sim.cmd_toggle_mount(312).get("ok", false)),
		"manual dismount is allowed")

	t.current = "save validity and ownership loss"
	var saved: Dictionary = sim.character_data(rider)
	t.near(float(saved["bike_service_meters"]), unchanged, 0.001,
		"remaining service is saved with survivor")
	var loaded := GameServer.new(world)
	var restored = loaded.add_player(312, "Mechanic", "", saved)
	t.near(restored.bike_service_meters, unchanged, 0.001,
		"relogin cannot refresh paid maintenance")
	t.eq(restored.mounted, false, "mount session state never saved")
	for invalid in [NAN, INF, -1.0, BikeService.MAX_METERS + 1.0, "500"]:
		var tampered: Dictionary = saved.duplicate(true)
		tampered["bike_service_meters"] = invalid
		t.eq(loaded.valid_character_data(tampered), false,
			"invalid saved service state rejected")
	var old_save: Dictionary = saved.duplicate(true)
	old_save.erase("bike_service_meters")
	t.eq(loaded.valid_character_data(old_save), true,
		"legacy characters without service remain loadable")
	rider.inventory.remove(Mounts.ITEM_ID, 1)
	sim._tick_players(0.05)
	t.eq(rider.bike_service_meters, 0.0,
		"losing the bike removes survivor-specific maintenance credit")
