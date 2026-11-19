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
	t.current = "expiry and no replay"
	sim.time = FieldCampfire.DURATION + 0.01
	t.check(not FieldCampfire.has_warmth(sim.campfires, camper.position, sim.time),
		"expired fire does not keep giving warmth before cleanup")
	sim._tick_world(0.01)
	t.eq(sim.campfires.size(), 0, "expired fire cleaned up")
	t.eq(sim.snapshot_for(93)["campfires"].size(), 0, "expired fire leaves snapshots")
