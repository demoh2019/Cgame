extends RefCounted
## A field fire is ephemeral and bounded, with no client-authoritative fuel
## or immunity and no accidental checkpoint / public identity leakage.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")
const Weather = preload("res://scripts/shared/weather.gd")


func _at(world, at: Vector2) -> Vector3:
	return Vector3(at.x, world.height_at(at.x, at.y), at.y)


func run(t) -> void:
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 17)
	var place: Vector2 = BarricadeTest.new()._find_place(world)
	t.current = "campfire dry placement"
	t.check(place != Vector2.ZERO, "found an open dry spot for a camp")
	if place == Vector2.ZERO:
		return
	var origin := place + Vector2(-2.8, 0.0)
	var camper = sim.add_player(93, "Wanderer")
	camper.position = _at(world, origin)
	t.eq(sim.cmd_light_campfire(999, place.x, place.y).get("reason"), "dead",
		"unknown client cannot create fire")
	t.eq(sim.cmd_light_campfire(93, NAN, place.y).get("reason"), "invalid_position",
		"invalid coordinates rejected before spending resources")
	t.eq(sim.cmd_light_campfire(93, place.x + 200, place.y).get("reason"), "out_of_range",
		"cannot place fire from afar")
	t.eq(sim.cmd_light_campfire(93, place.x, place.y).get("reason"), "missing_materials",
		"requires real gathered resources")
	camper.inventory.add("wood_1", 10)
	camper.inventory.add("stone_1", 4)
	var wood_before: int = camper.inventory.count("wood_1")
	var stone_before: int = camper.inventory.count("stone_1")
	var started: Dictionary = sim.cmd_light_campfire(93, place.x, place.y)
	t.check(bool(started.get("ok", false)), "funded campsite is created")
	if not bool(started.get("ok", false)):
		return
	var id: int = int(started["id"])
	t.eq(camper.inventory.count("wood_1"), wood_before - 3, "wood fuel spent once")
	t.eq(camper.inventory.count("stone_1"), stone_before - 1, "stone base spent once")
	t.eq(sim.campfires.size(), 1, "one temporary server-owned fire")
	t.eq(sim.cmd_light_campfire(93, place.x, place.y).get("reason"), "blocked",
		"overlapping fires rejected")
	t.eq(camper.inventory.count("wood_1"), wood_before - 3, "invalid cast does not spend materials")
	t.check(not world.dynamic_blockers.has(id), "campfire does not block world movement")

	t.current = "warmth, replication and nearby survivors"
	t.check(FieldCampfire.has_warmth(sim.campfires, _at(world, place), sim.time),
		"nearby survivor gets fire warmth")
	t.check(not FieldCampfire.has_warmth(sim.campfires, _at(world, place + Vector2(15, 0)), sim.time),
		"distant survivor stays exposed")
	camper.position = _at(world, place)
	var snap: Dictionary = sim.snapshot_for(93)
	t.check(bool(snap["you"]["campfire_warm"]), "server snapshot reports current shelter")
	t.eq(snap["campfires"].size(), 1, "nearby fire is replicated")
	t.check(not snap["campfires"][0].has("owner"), "server does not expose owner peer ID")
	t.check(not snap["campfires"][0].has("owner_account"), "account ID never exposed")
	var second = sim.add_player(94, "Neighbor")
	second.position = _at(world, place + Vector2(1, 0))
	t.check(bool(sim.snapshot_for(94)["you"]["campfire_warm"]), "shared camp warms another player")
	var distant = sim.add_player(95, "Traveler")
	distant.position = _at(world, place + Vector2(200, 0))
	t.eq(sim.snapshot_for(95)["campfires"].size(), 0, "distant peers get no fire positions")

	t.current = "weather protection"
	var survivor_weather = camper.survival
	survivor_weather.exposure = 35.0
	sim._tick_players(1.0)
	t.check(survivor_weather.exposure < 35.0,
		"fire shelter lowers existing cold exposure")
	var checkpoint: Dictionary = Persist.capture(sim)
	t.check(not checkpoint.has("campfires"), "short-lived fire is not persisted as an account wall")
	t.current = "server-authoritative cooperative refueling"
	var prior_expiry: float = float(sim.campfires[id]["expires"])
	t.eq(sim.cmd_refuel_campfire(999, id).get("reason"), "dead",
			"unregistered peer cannot spend fuel")
	t.eq(sim.cmd_refuel_campfire(93, -1).get("reason"), "no_fire",
			"unknown fire cannot consume inventory")
	distant.inventory.add("wood_1", 4)
	var far_wood: int = distant.inventory.count("wood_1")
	t.eq(sim.cmd_refuel_campfire(95, id).get("reason"), "out_of_range",
			"remote player cannot refuel a campfire")
	t.eq(distant.inventory.count("wood_1"), far_wood,
			"distance rejection leaves source items untouched")
	var refuel_wood: int = camper.inventory.count("wood_1")
	var fueled: Dictionary = sim.cmd_refuel_campfire(93, id)
	t.check(bool(fueled.get("ok", false)), "living owner can add wood")
	t.eq(camper.inventory.count("wood_1"), refuel_wood - 2,
			"two wood units consumed exactly once")
	t.near(float(sim.campfires[id]["expires"]), prior_expiry + FieldCampfire.REFUEL_SECONDS,
			0.001, "burn time extends by 120 seconds")
	t.eq(sim.cmd_refuel_campfire(94, id).get("reason"), "missing_materials",
			"other survivor cannot refuel without timber")
	second.inventory.add("wood_1", 3)
	var second_wood: int = second.inventory.count("wood_1")
	t.check(bool(sim.cmd_refuel_campfire(94, id).get("ok", false)),
			"another survivor can cooperatively refuel the same fire")
	t.eq(second.inventory.count("wood_1"), second_wood - 2,
			"contributing player pays their own fuel")
	t.near(float(sim.campfires[id]["expires"]), prior_expiry + 2.0 * FieldCampfire.REFUEL_SECONDS,
			0.001, "two refuels extend time twice")
	t.eq(sim.cmd_refuel_campfire(93, id).get("reason"), "full_duration",
			"burn-duration cap rejects extra fuel")
	t.eq(camper.inventory.count("wood_1"), refuel_wood - 2,
			"refused fuel does not destroy more inventory")
	var public: Dictionary = sim.snapshot_for(94)
	t.check(float(public["campfires"][0]["remaining"]) > FieldCampfire.DURATION,
			"both clients receive the updated remaining time")
	t.check(not public["campfires"][0].has("owner"),
			"refueled fire still does not expose account or peer")

	t.current = "expiry and no replay"
	sim.time = float(sim.campfires[id]["expires"]) + 0.01
	t.check(not FieldCampfire.has_warmth(sim.campfires, camper.position, sim.time),
		"expired fire does not keep giving warmth before cleanup")
	t.eq(sim.cmd_refuel_campfire(93, id).get("reason"), "expired",
			"expired fire cannot be refueled after deadline")
	sim._tick_world(0.01)
	t.eq(sim.campfires.size(), 0, "expired fire cleaned up")
	t.eq(sim.snapshot_for(93)["campfires"].size(), 0, "expired fire leaves snapshots")
