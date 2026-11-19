extends RefCounted
## Genuine campfire, server-owned recovery, danger and paid ration checks.
const Defs = preload("res://scripts/shared/defs.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const FieldRest = preload("res://scripts/shared/field_rest.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func run(t) -> void:
	t.current = "paid field respite requires live fire and clean water"
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 212)
	var site: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(site != Vector2.ZERO, "find usable campfire terrain")
	if site == Vector2.ZERO:
		return
	var camper = sim.add_player(501, "Expedition Survivor")
	camper.position = _at(world, site + Vector2(-2.8, 0.0))
	camper.survival.health = 45.0
	camper.survival.stamina = 40.0
	camper.survival.hunger = 35.0
	camper.survival.thirst = 40.0
	t.eq(sim.cmd_rest(501).get("reason", ""), "no_station",
		"remote restoration cannot occur without a live fire")
	camper.inventory.add("wood_1", 3)
	camper.inventory.add("stone_1", 1)
	camper.inventory.add("cooked_fish", 1)
	camper.inventory.add("cooked_fish_2", 1)
	camper.inventory.add("water_bottle", 1)
	var lit: Dictionary = sim.cmd_light_campfire(501, site.x, site.y)
	t.check(bool(lit.get("ok", false)), "pay for and place real server campfire")
	if not bool(lit.get("ok", false)):
		return
	camper.position = _at(world, site)
	var before_water: int = camper.inventory.count("water_bottle")
	var success: Dictionary = sim.cmd_rest(501)
	t.check(bool(success.get("ok", false)) and bool(success.get("field", false)),
		"server distinguishes field respite from hub sanctuary rest")
	t.eq(camper.inventory.count("water_bottle"), before_water - 1, "clean water consumed once")
	t.eq(camper.inventory.count("cooked_fish"), 0, "one cooked T1 fish consumed")
	t.eq(camper.inventory.count("cooked_fish_2"), 1, "valuable T2 fish conserved")
	t.near(camper.survival.health, 45.0 + FieldRest.HEALTH, 0.001, "limited field healing")
	t.near(camper.survival.stamina, 40.0 + FieldRest.STAMINA, 0.001, "bounded stamina restoration")
	t.near(camper.survival.hunger, 35.0 + FieldRest.HUNGER, 0.001, "food improves hunger")
	t.near(camper.survival.thirst, 40.0 + FieldRest.THIRST, 0.001, "water improves thirst")
	t.near(camper.rest_cooldown, CampRest.COOLDOWN, 0.001, "hub cooldown is shared")
	t.eq(sim.cmd_rest(501).get("reason", ""), "cooldown", "replay cannot heal twice")
	camper.rest_cooldown = 0.0
	camper.survival.health = 40.0
	camper.inventory.remove("water_bottle", camper.inventory.count("water_bottle"))
	t.eq(sim.cmd_rest(501).get("reason", ""), "missing_items",
		"insufficient water cannot spend the surviving fish")
	t.eq(camper.inventory.count("cooked_fish_2"), 1, "failed rest retains high-tier ration")
	camper.inventory.add("water_bottle", 2)
	camper.attack_timer = 1.0
	t.eq(sim.cmd_rest(501).get("reason", ""), "in_combat", "combat denies field healing")
	camper.attack_timer = 0.0

	t.current = "nearby infected make field recovery unsafe"
	var infected = Zombie.new(sim.new_id(), "walker", camper.position + Vector3(4.0, 0.0, 0.0))
	sim.zombies[infected.id] = infected
	var before: Dictionary = camper.inventory.to_dict()
	t.eq(sim.cmd_rest(501).get("reason", ""), "infected_near", "live infected prevents resting")
	t.eq(camper.inventory.to_dict(), before, "refused unsafe rest never spends supplies")
	sim.zombies.clear()
	t.check(bool(sim.cmd_rest(501).get("ok", false)), "field rest resumes after enemy leaves")
	t.eq(camper.inventory.count("cooked_fish_2"), 0, "T2 fish may be used as field ration")
	camper.rest_cooldown = 0.0

	t.current = "hostile survivor in PvP range blocks instant recovery"
	camper.position = _at(world, Vector2(800.0, 800.0))
	camper.survival.health = 30.0
	camper.inventory.add("canned_food", 1)
	camper.inventory.add("water_bottle", 1)
	var rival = sim.add_player(502, "Hostile Player")
	rival.position = _at(world, Vector2(804.0, 800.0))
	t.check(world.zone_at(800.0, 800.0) >= 2, "test position is full-loot territory")
	sim.campfires[999] = {"id": 999, "x": 800.0, "z": 800.0,
		"y": camper.position.y, "expires": sim.time + 120.0}
	var ration_before: int = camper.inventory.count("canned_food")
	t.eq(sim.cmd_rest(501).get("reason", ""), "enemy_player_near",
		"hostile player nearby in red/black zone prevents field healing")
	t.eq(camper.inventory.count("canned_food"), ration_before,
		"hostile-denied rest does not consume scarce food")
	rival.position = _at(world, Vector2(830.0, 800.0))
	t.check(bool(sim.cmd_rest(501).get("ok", false)),
		"when the PvP threat retreats, the shared campfire can be used")

	t.current = "expired fire and fully rested survivor never waste food"
	camper.rest_cooldown = 0.0
	sim.time += 301.0
	t.eq(sim.cmd_rest(501).get("reason", ""), "no_station",
		"burned-out fire cannot mint health")
	var pack := sim.add_player(503, "Prepared Survivor")
	pack.survival.health = Defs.MAX_HEALTH
	pack.survival.stamina = Defs.MAX_STAMINA
	pack.survival.hunger = 100.0
	pack.survival.thirst = 100.0
	t.check(not CampRest.needs_recovery(pack.survival),
		"fully recovered player cannot consume extra camp rations")
