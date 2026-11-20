extends RefCounted
## Bicycle terrain handling and shared authoritative movement.

const Defs = preload("res://scripts/shared/defs.gd")
const BikeTerrain = preload("res://scripts/shared/bike_terrain.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class TestTerrain:
	extends RefCounted
	var biome := "plains"
	var slope := 0.0

	func height_at(x: float, _z: float) -> float:
		return 3.0 + x * slope

	func biome_at(_x: float, _z: float) -> String:
		return biome

	func blockers_near(_x: float, _z: float, _range: float) -> Array:
		return []


func run(t) -> void:
	var map := TestTerrain.new()
	var start := Vector3(0.0, 3.0, 0.0)
	var input := {"x": 1.0, "z": 0.0, "mounted": true}
	t.current = "real bicycle surface resistance"
	var firm := Movement.step(map, start, input, 0.1)
	t.near(firm.x, Defs.WALK_SPEED * Mounts.SPEED_FACTOR * 0.1,
		0.0001, "firm terrain keeps the designed bike speed")
	map.biome = "forest"
	var forest := Movement.step(map, start, input, 0.1)
	map.biome = "beach"
	var sand := Movement.step(map, start, input, 0.1)
	map.biome = "swamp"
	var mud := Movement.step(map, start, input, 0.1)
	t.check(firm.x > forest.x and forest.x > sand.x and sand.x > mud.x,
		"bicycle loses traction on roots, sand and mud in order")
	var foot := Movement.step(map, start, {"x": 1.0}, 0.1)
	t.near(foot.x, Defs.WALK_SPEED * 0.1, 0.0001,
		"terrain changes bicycle travel, not ordinary pedestrian movement")
	t.check(mud.x > 0.0, "a bicycle still moves slowly through mud")

	t.current = "climbing and descending"
	map.biome = "plains"
	map.slope = 0.20
	var uphill := Movement.step(map, start, input, 0.1)
	map.slope = -0.20
	var downhill := Movement.step(map, start, input, 0.1)
	t.check(uphill.x < firm.x and downhill.x > firm.x,
		"uphill slows pedaling and gentle downhill speeds it up")
	map.slope = 1000.0
	t.near(BikeTerrain.speed_factor(map, start, Vector2.RIGHT),
		BikeTerrain.MIN_TRACTION, 0.0001, "extreme climbs cannot reverse or freeze time")
	map.slope = -1000.0
	t.check(BikeTerrain.speed_factor(map, start, Vector2.RIGHT) <=
		BikeTerrain.MAX_TRACTION, "downhill boost has a hard cap")
	t.near(BikeTerrain.speed_factor(map, start, Vector2(500, 0)),
		BikeTerrain.speed_factor(map, start, Vector2.RIGHT), 0.0001,
		"malformed direction magnitude cannot create extra downhill speed")

	t.current = "untrusted and stalled movement"
	map.slope = 0.0
	t.eq(Movement.step(map, start, {"x": NAN, "mounted": true}, 0.1),
		start, "nonfinite steering cannot move the bike")
	t.eq(Movement.step(map, start, input, INF), start,
		"invalid frame duration cannot teleport the rider")
	var invalid_bonus := Movement.step(map, start,
		{"x": 1.0, "mounted": true, "speed_bonus": NAN}, 0.1)
	t.near(invalid_bonus.x, firm.x, 0.0001,
		"nonfinite bonus does not bypass capped speed rules")
	t.eq(Movement.step(map, start, {"mounted": true}, 0.1), start,
		"idling bicycle does not drift")

	t.current = "server uses exactly the shared terrain path"
	var world := WorldGen.new(42)
	var server := GameServer.new(world)
	var rider = server.add_player(83, "BikeTerrain")
	rider.inventory.add(Mounts.ITEM_ID, 1)
	t.check(bool(server.cmd_toggle_mount(83).get("mounted", false)),
		"real server owns the bike state")
	var origin: Vector3 = rider.position
	var expected := Movement.step(world, origin, {
		"x": 1.0, "z": 0.0, "mounted": true,
		"cargo_factor": rider.inventory.movement_factor(rider.skills.bonus("carry_capacity")),
		"injury_factor": 1.0, "speed_bonus": rider.skills.bonus("move_speed")
	}, 0.1)
	rider.input_budget = 0.1
	server.submit_input(83, 1, 1.0, 0.0, false, 0.0, 0.1)
	t.near(rider.position.distance_to(expected), 0.0, 0.0001,
		"server movement matches client-predictable terrain physics")
