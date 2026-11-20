extends RefCounted
## Server, predictive movement and sprint stamina agree at coastal crossings.
const Defs = preload("res://scripts/shared/defs.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WadingTravel = preload("res://scripts/shared/wading_travel.gd")
const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CoastTest = preload("res://tests/test_wading_wetness.gd")

class FlatShallows:
	extends RefCounted
	var elevation: float = 2.0
	func height_at(_x: float, _z: float) -> float:
		return elevation
	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return []
	func biome_at(_x: float, _z: float) -> String:
		return "beach"
	func road_coverage_at(_x: float, _z: float) -> float:
		return 0.0


func run(t) -> void:
	t.current = "shoreline depth drives real walking and cycling drag"
	var world := FlatShallows.new()
	var start := Vector3(0, 2, 0)
	t.eq(WadingTravel.factor(world, start, false), 1.0,
		"dry ground retains ordinary movement")
	t.check(WadingTravel.can_sprint(world, start),
		"dry players can still sprint")
	world.elevation = -0.15
	t.check(WadingTravel.can_sprint(world, start), "ankle water still permits sprinting")
	var ankle_factor: float = WadingTravel.factor(world, start, false)
	world.elevation = -0.50
	t.check(not WadingTravel.can_sprint(world, start),
		"water above the sprint threshold prevents running")
	var foot_drag: float = WadingTravel.factor(world, start, false)
	var bike_drag: float = WadingTravel.factor(world, start, true)
	t.check(foot_drag < ankle_factor and bike_drag < foot_drag,
		"deeper water slows walking and bicycle handling more")
	t.near(foot_drag, 0.825, 0.0001, "half-meter water slows walking 17.5 percent")
	t.near(bike_drag, 0.775, 0.0001, "half-meter water slows bikes 22.5 percent")
	var running: Vector3 = Movement.step(world, start,
		{"x": 1.0, "sprint": true}, 0.1)
	t.near(running.x, Defs.WALK_SPEED * foot_drag * 0.1, 0.0001,
		"forged sprint flag cannot bypass deep-wading walking pace")
	var cycling: Vector3 = Movement.step(world, start,
		{"x": 1.0, "mounted": true}, 0.1)
	t.check(cycling.x > running.x, "bicycle still moves, but with water resistance")
	world.elevation = -0.90
	t.check(WadingTravel.factor(world, start, false) < foot_drag,
		"near-waist water is even slower")
	world.elevation = -1.01
	t.eq(WadingTravel.factor(world, start, false), 1.0,
		"uncrossable deep water does not invent a movement slowdown")
	world.elevation = NAN
	t.eq(WadingTravel.factor(world, start, true), 1.0,
		"invalid terrain cannot yield infinite movement penalties")
	t.eq(WadingTravel.factor(world, Vector3(NAN, 0, 0), false), 1.0,
		"invalid coordinates cannot change walk speed")

	t.current = "server rejects knee-deep sprint without consuming energy"
	var terrain := WorldGen.new(42)
	var coast: Vector2 = CoastTest.new()._find_wade(terrain)
	t.check(coast.is_finite(), "real world has a traversable submerged shoreline")
	if not coast.is_finite():
		return
	var server := GameServer.new(terrain, 42)
	var traveler = server.add_player(61, "Wader")
	traveler.position = Vector3(coast.x, terrain.height_at(coast.x, coast.y), coast.y)
	var depth: float = WadingWetness.depth_at(terrain, traveler.position)
	t.check(depth > WadingTravel.SPRINT_MAX_DEPTH and depth <= 1.0,
		"real explorer stands in water too deep for sprinting")
	var toward_land: Vector2 = -coast.normalized()
	var before: Vector3 = traveler.position
	var energy_before: float = traveler.survival.stamina
	var expected: Vector3 = Movement.step(terrain, before,
		{"x": toward_land.x, "z": toward_land.y, "weather_time": server.time},
		0.1)
	traveler.input_budget = 0.1
	server.submit_input(61, 1, toward_land.x, toward_land.y, true, 0.0, 0.1)
	t.near(traveler.position.distance_to(expected), 0.0, 0.0001,
		"server applies identical water drag as shared client movement")
	t.near(traveler.survival.stamina, energy_before, 0.0001,
		"invalid deep-water sprint spends no stamina")
	t.check(traveler.run_meters < 0.001,
		"deep-water input never awards sprint athletic progress")
	var snap: Dictionary = server.snapshot_for(61)["you"]
	t.check(float(snap["wading_depth_m"]) >= 0.0,
		"existing private water-depth HUD remains compatible")
