extends RefCounted
## Days After-style heavy inventory makes survivors audible; Albion-style
## cargo remains authoritative and stealth movement gives a real tradeoff.

const CargoRattle = preload("res://scripts/shared/cargo_rattle.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WindHearing = preload("res://scripts/shared/wind_hearing.gd")


func _think(enemy, world, player_pos: Vector3, sound: float, safe: bool = false) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var data := {1: {"position": player_pos, "alive": true, "safe": safe,
		"noise": sound, "wind": Vector2.ZERO}}
	for step in 5:
		enemy.think(world, data, 0.1, rng)
	return enemy.target_id


func run(t) -> void:
	t.current = "derived, bounded weight noise with authentic movement"
	t.eq(CargoRattle.radius(1.0, 0.1, false, false), 0.0,
		"light backpack remains silent while walking")
	t.eq(CargoRattle.radius(0.5, 0.0, false, false), 0.0,
		"stationary heavy backpack does not create sound")
	t.eq(CargoRattle.radius(0.5, 0.1, true, false), 0.0,
		"crouching quiets heavy cargo")
	t.eq(CargoRattle.radius(0.5, 0.1, false, true), 0.0,
		"riding continues to use independent bike-rattle rules")
	t.eq(CargoRattle.radius(NAN, 0.1, false, false), 0.0,
		"invalid carried-load factor cannot forge noise")
	t.eq(CargoRattle.radius(0.5, INF, false, false), 0.0,
		"nonfinite claimed travel cannot generate footfalls")
	t.check(CargoRattle.radius(0.8, 0.1, false, false) <
		CargoRattle.radius(0.5, 0.1, false, false),
		"heavier real backpack rattles farther")
	t.near(CargoRattle.radius(0.5, 0.1, false, false),
		CargoRattle.MAX_RADIUS, 0.0001, "maximum rattle radius stays bounded")
	t.check(CargoRattle.MAX_RADIUS < Defs.GUNSHOT_NOISE_RADIUS,
		"heavy loot does not become louder than gunfire")

	t.current = "real server backpack noise is created only after displacement"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 42)
	var survivor = server.add_player(301, "Miner")
	survivor.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	survivor.inventory.add("stone_1", 50)
	t.check(survivor.inventory.movement_factor() <= 0.5001,
		"genuine 100 kg mining pack is overburdened")
	var initial: Vector3 = survivor.position
	var stamina_before: float = survivor.survival.stamina
	survivor.input_budget = 0.1
	server.submit_input(301, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.check(survivor.position.distance_to(initial) > 0.01,
		"server verified that the heavy player actually walked")
	t.near(survivor.noise_radius, CargoRattle.MAX_RADIUS, 0.0001,
		"server derives pack sound only from real inventory weight and movement")
	t.near(survivor.noise_timer, CargoRattle.NOISE_SECONDS, 0.0001,
		"short noise window integrates with existing infected senses")
	t.eq(survivor.survival.stamina, stamina_before,
		"too-heavy character cannot forge sprint or spend sprint stamina")
	var weight_before: float = survivor.inventory.total_weight()
	survivor.noise_radius = 0.0
	survivor.noise_timer = 0.0
	survivor.input_budget = 0.1
	server.submit_input(301, 2, 0.0, 0.0, false, 0.0, 0.1)
	t.eq(survivor.noise_radius, 0.0,
		"no new noise on still input even with full load")
	survivor.input_budget = 0.1
	server.submit_input(301, 3, 1.0, 0.0, false, 0.0, 0.1, true)
	t.eq(survivor.noise_radius, 0.0,
		"crouching with a heavy backpack does not trigger rattle")
	t.eq(survivor.inventory.total_weight(), weight_before,
		"movement never consumes or duplicates backpack contents")
	survivor.inventory.remove("stone_1", 50)
	survivor.input_budget = 0.1
	server.submit_input(301, 4, 1.0, 0.0, false, 0.0, 0.1, false)
	t.eq(survivor.noise_radius, 0.0,
		"unloading returns ordinary quiet walking")
	t.near(float(server.snapshot_for(301)["you"]["carry_kg"]),
		survivor.inventory.total_weight(), 0.0001,
		"HUD weight still reflects only authoritative inventory")
	t.check(not server.snapshot_for(301)["you"].has("noise_radius"),
		"clients cannot override or observe hidden server hearing internals")

	t.current = "infected notice burdened walker, wind still affects footfalls"
	var ground: float = WorldGen.HUB_HEIGHT
	var noisy := Zombie.new(10, "walker", Vector3(23.0, ground, 0.0))
	t.eq(_think(noisy, world, Vector3(0.0, ground, 0.0), CargoRattle.MAX_RADIUS), 1,
		"loaded walk can alert an infected beyond normal visual range")
	var quiet := Zombie.new(11, "walker", Vector3(23.0, ground, 0.0))
	t.eq(_think(quiet, world, Vector3(0.0, ground, 0.0), 0.0), -1,
		"same unloaded walker cannot be heard at that distance")
	var protected := Zombie.new(12, "walker", Vector3(23.0, ground, 0.0))
	t.eq(_think(protected, world, Vector3(0.0, ground, 0.0),
		CargoRattle.MAX_RADIUS, true), -1,
		"safe hub always prevents infected aggression regardless of footfalls")
	var downwind: float = WindHearing.radius(CargoRattle.MAX_RADIUS,
		Vector2(1.6, 0.0), Vector2.ZERO, Vector2(26.0, 0.0), 33.0)
	t.check(downwind > 26.0,
		"existing regional wind naturally carries heavy cargo noise downwind")
