extends RefCounted
## Server-paid storm fuel protects only live nearby fires, never persistent bases.
const Defs = preload("res://scripts/shared/defs.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const Briquette = preload("res://scripts/shared/stormproof_briquette.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "stormproof fuel: recipe, edge cases and fractional expiry"
	t.eq(Defs.item(Briquette.ITEM_ID).get("kind"), "fire_briquette", "item registered")
	t.eq(Defs.recipes()[Briquette.ITEM_ID]["inputs"],
		{"wood_1": 3, "fiber_1": 2, "scrap": 1}, "field craft uses real fuel resources")
	t.eq(Defs.recipes()[Briquette.ITEM_ID]["station"], "",
		"fuel can be made away from the workbench")
	t.near(Briquette.exposed_seconds(1.0, 10.0, {}), 1.0, 0.001,
		"normal unshielded storm still doubles burn")
	t.near(Briquette.exposed_seconds(1.0, 10.0, {"stormproof_until": 20.0}),
		0.0, 0.001, "shield protects entire tick")
	t.near(Briquette.exposed_seconds(1.0, 10.0, {"stormproof_until": 9.5}),
		0.5, 0.001, "expiry inside tick applies only unprotected fraction")
	t.near(Briquette.exposed_seconds(INF, 10.0, {}), 0.0, 0.001,
		"invalid duration cannot alter fire")
	var world := WorldGen.new(198)
	var sim := GameServer.new(world, 198)
	var camper = sim.add_player(12, "Firekeeper")
	var helper = sim.add_player(13, "Companion")
	var point := Vector2(730.0, 700.0)
	camper.position = Vector3(point.x, world.height_at(point.x, point.y), point.y)
	helper.position = camper.position + Vector3(0.9, 0.0, 0.0)
	t.current = "stormproof fuel: close-range payment and shared effect"
	t.eq(sim.cmd_use(12, Briquette.ITEM_ID).get("reason"), "not_carried",
		"cannot apply without an inventory item")
	camper.inventory.add(Briquette.ITEM_ID, 2)
	t.eq(sim.cmd_use(12, Briquette.ITEM_ID).get("reason"), "no_fire",
		"no fire cannot charge player")
	t.eq(camper.inventory.count(Briquette.ITEM_ID), 2, "failed use leaves stock")
	var id := 903
	sim.time = 600.0
	sim.campfires[id] = {"id": id, "x": point.x, "y": camper.position.y,
		"z": point.y, "expires": sim.time + 200.0, "owner": 12}
	camper.attack_timer = 1.0
	t.eq(sim.cmd_use(12, Briquette.ITEM_ID).get("reason"), "in_combat",
		"cannot reinforce in combat")
	camper.attack_timer = 0.0
	camper.position += Vector3(30.0, 0.0, 0.0)
	t.eq(sim.cmd_use(12, Briquette.ITEM_ID).get("reason"), "no_fire",
		"distant survivor cannot modify a shared fire")
	camper.position = Vector3(point.x, world.height_at(point.x, point.y), point.y)
	var out: Dictionary = sim.cmd_use(12, Briquette.ITEM_ID)
	t.check(bool(out.get("ok", false)), "legitimate field fuel application succeeds")
	t.eq(camper.inventory.count(Briquette.ITEM_ID), 1, "exactly one item debited")
	t.near(float(sim.campfires[id]["expires"]), sim.time + 320.0, 0.001,
		"real burn lifetime increases by 120 seconds")
	t.near(float(sim.campfires[id]["stormproof_until"]), sim.time + 90.0,
		0.001, "storm shield granted for 90 seconds")
	t.eq(sim.cmd_use(12, Briquette.ITEM_ID).get("reason"), "already_stormproof",
		"no stacked reapplications before shield expires")
	t.eq(camper.inventory.count(Briquette.ITEM_ID), 1, "duplicate preserves consumable")
	var snap: Dictionary = sim.snapshot_for(13)
	t.eq(snap["campfires"].size(), 1, "other survivor sees the shared fire")
	t.near(float(snap["campfires"][0]["stormproof_seconds"]), 90.0,
		0.001, "nearby players see weatherproof status")
	t.check(not snap["campfires"][0].has("owner"),
		"public state does not leak the fire owner's identity")
	t.current = "stormproof fuel: real storm tick and expiration"
	var storm_time := -1.0
	for phase in range(100):
		var sample := float(phase) * Weather.CHANGE_SECONDS + 1.0
		if str(Weather.conditions(world, point.x, point.y, sample).get("condition", "")) == "storm":
			storm_time = sample
			break
	t.check(storm_time >= 0.0, "deterministic timeline includes storm")
	if storm_time < 0.0:
		return
	sim.time = storm_time
	sim.campfires[id]["expires"] = sim.time + 200.0
	sim.campfires[id]["stormproof_until"] = sim.time + 5.0
	sim.time += 1.0
	sim._tick_world(1.0)
	t.near(float(sim.campfires[id]["expires"]) - sim.time, 199.0, 0.001,
		"active shield prevents extra storm fuel loss")
	sim.time += 5.0
	sim._tick_world(5.0)
	t.near(float(sim.campfires[id]["expires"]) - sim.time, 193.0, 0.001,
		"only unshielded 1 second costs extra fuel across deadline")
	t.current = "stormproof fuel: bounded normal refueling"
	sim.time = 100.0
	sim.campfires[id]["expires"] = sim.time + FieldCampfire.MAX_REMAINING_SECONDS - 50.0
	sim.campfires[id]["stormproof_until"] = 0.0
	t.eq(sim.cmd_use(12, Briquette.ITEM_ID).get("reason"), "full_duration",
		"nearly full fires cannot waste storm briquettes")
	t.eq(camper.inventory.count(Briquette.ITEM_ID), 1, "refusal is atomic")
