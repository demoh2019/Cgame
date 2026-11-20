extends RefCounted
## Storm-driven mud changes legitimate foot/bike travel on both peers.
## Movement cannot accept client-supplied traction: server owns world time.

const Defs = preload("res://scripts/shared/defs.gd")
const StormMud = preload("res://scripts/shared/storm_mud.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

class FlatWorld:
	extends RefCounted
	var world_seed: int = 131
	var biome: String = "swamp"
	var road: float = 0.0
	var safe: bool = false

	func biome_at(_x: float, _z: float) -> String:
		return biome

	func road_coverage_at(_x: float, _z: float) -> float:
		return road

	func is_safe(_x: float, _z: float) -> bool:
		return safe

	func height_at(_x: float, _z: float) -> float:
		return 3.0

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return []


func _phase(world, storm: bool, x: float = 350.0, z: float = 350.0) -> float:
	for phase in range(100):
		var now: float = float(phase) * Weather.CHANGE_SECONDS + 1.0
		var actual: Dictionary = Weather.conditions(world, x, z, now)
		if (str(actual.get("condition", "")) == "storm") == storm:
			return now
	return -1.0


func run(t) -> void:
	t.current = "rain terrain slows only exposed ground, roads keep grip"
	var rain := {"condition": "storm", "sheltered": false}
	var clear := {"condition": "clear", "sheltered": false}
	t.eq(StormMud.traction(clear, "swamp", 0.0, false), 1.0,
		"clear weather retains historic walking speed")
	t.eq(StormMud.traction({"condition": "storm", "sheltered": true},
		"swamp", 0.0, false), 1.0, "protected hub does not become slippery")
	t.near(StormMud.traction(rain, "swamp", 0.0, false), 0.82, 0.0001,
		"swamp rain reduces foot traction by 18 percent")
	t.near(StormMud.traction(rain, "swamp", 0.0, true), 0.76, 0.0001,
		"bike loses more traction than boots in wet swamp")
	t.check(StormMud.traction(rain, "swamp", 1.0, false) >
		StormMud.traction(rain, "swamp", 0.0, false),
		"built road reduces the foot mud penalty")
	t.check(StormMud.traction(rain, "swamp", 1.0, true) >
		StormMud.traction(rain, "swamp", 0.0, true),
		"built road reduces bike skidding")
	t.check(StormMud.traction(rain, "swamp", 1.0, true) < 1.0,
		"even well-used roads do not create total rain immunity")
	t.eq(StormMud.traction(rain, "swamp", NAN, true), 1.0,
		"invalid road samples cannot supply unsafe traction")
	t.eq(StormMud.traction(rain, "unknown", 0.0, true), 1.0,
		"unknown terrain has no invented mud penalty")

	t.current = "shared predicted movement obeys deterministic seeded weather"
	var ground := FlatWorld.new()
	var position := Vector3(350.0, 3.0, 350.0)
	var storm_at: float = _phase(ground, true)
	var clear_at: float = _phase(ground, false)
	t.check(storm_at >= 0.0 and clear_at >= 0.0,
		"seeded world cycles reliably between storms and clear sky")
	if storm_at < 0.0 or clear_at < 0.0:
		return
	var walk := {"x": 1.0, "z": 0.0, "weather_time": storm_at}
	var dry := walk.duplicate()
	dry["weather_time"] = clear_at
	var rain_walk: Vector3 = Movement.step(ground, position, walk, 0.1)
	var clear_walk: Vector3 = Movement.step(ground, position, dry, 0.1)
	t.check(rain_walk.x < clear_walk.x,
		"actual rain slows shared movement without altering the input command")
	t.near(rain_walk.x - position.x,
		Defs.WALK_SPEED * 0.1 * StormMud.factor(ground, position, storm_at, false),
		0.0001, "movement uses exact weather-derived foot traction")
	ground.road = 1.0
	var road_walk: Vector3 = Movement.step(ground, position, walk, 0.1)
	t.check(road_walk.x > rain_walk.x,
		"roads genuinely help walkers travel during rain")
	ground.road = 0.0
	var bike_input := {"x": 1.0, "mounted": true, "weather_time": storm_at}
	var wet_bike: Vector3 = Movement.step(ground, position, bike_input, 0.1)
	bike_input["weather_time"] = clear_at
	var dry_bike: Vector3 = Movement.step(ground, position, bike_input, 0.1)
	t.check(wet_bike.x < dry_bike.x,
		"same mounted movement loses traction during downpour")
	ground.safe = true
	t.eq(StormMud.factor(ground, position, storm_at, true), 1.0,
		"starter settlement stays sheltered despite rain elsewhere")
	t.eq(StormMud.factor(ground, Vector3(NAN, 3, 0), storm_at, true), 1.0,
		"invalid world position never changes movement")
	t.eq(StormMud.factor(ground, position, INF, true), 1.0,
		"invalid world clock does not make a player crawl")

	t.current = "server input derives rain factor itself and replicates privately"
	var world := WorldGen.new(501)
	var sim := GameServer.new(world, 501)
	var traveler = sim.add_player(31, "Storm Traveler")
	var site := Vector2(350.0, 350.0)
	var found := false
	for xi in range(10):
		for zi in range(10):
			var candidate := Vector2(240.0 + float(xi) * 20.0,
				240.0 + float(zi) * 20.0)
			if world.is_safe(candidate.x, candidate.y) or world.is_water(candidate.x, candidate.y):
				continue
			if not Movement._is_free(world, candidate) or not Movement._is_free(
					candidate + Vector2(1.0, 0.0)):
				continue
			site = candidate
			found = true
			break
		if found:
			break
	t.check(found, "real terrain offers an exposed passable test route")
	if not found:
		return
	traveler.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	storm_at = _phase(world, true, site.x, site.y)
	t.check(storm_at >= 0.0, "real regional weather produces a storm")
	if storm_at < 0.0:
		return
	sim.time = storm_at
	var start: Vector3 = traveler.position
	var expected: Vector3 = Movement.step(world, start,
		{"x": 1.0, "weather_time": sim.time,
		"cargo_factor": traveler.inventory.movement_factor()}, 0.1)
	traveler.input_budget = 0.1
	sim.submit_input(traveler.id, 1, 1.0, 0.0, false, 0.0, 0.1)
	t.near(traveler.position.distance_to(expected), 0.0, 0.0001,
		"real server uses the same seeded ground friction as client prediction")
	var snapshot: Dictionary = sim.snapshot_for(traveler.id)["you"]
	t.near(float(snapshot["storm_mud_factor"]),
		StormMud.factor(world, traveler.position, sim.time, false), 0.0001,
		"private HUD factor is computed by the authoritative world")
	t.check(not snapshot.has("weather_time"),
		"client never obtains a writable server traction parameter")
