extends RefCounted
## Seeded road contact, shared bike grip and server-owned travel speed.
const Defs = preload("res://scripts/shared/defs.gd")
const RoadTravel = preload("res://scripts/shared/road_travel.gd")
const WorldRoads = preload("res://scripts/shared/world_roads.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const BikeTerrain = preload("res://scripts/shared/bike_terrain.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

class FakeRoad:
	extends RefCounted
	var coverage_value := 0.0
	var biome := "swamp"
	func road_coverage_at(_x: float, _z: float) -> float:
		return coverage_value
	func biome_at(_x: float, _z: float) -> String:
		return biome
	func height_at(_x: float, _z: float) -> float:
		return 3.0
	func blockers_near(_x: float, _z: float, _distance: float) -> Array:
		return []

func run(t) -> void:
	t.current = "road width, ends and nonfinite geometry"
	var segment: Array = [[Vector2(-10, 0), Vector2(10, 0)]]
	t.eq(WorldRoads.coverage_on_segments(Vector2.ZERO, segment), 1.0,
		"road centre offers full support")
	t.eq(WorldRoads.coverage_on_segments(Vector2(0, 6), segment), 0.0,
		"off-road ground remains unaffected")
	var shoulder: float = WorldRoads.coverage_on_segments(Vector2(0, 2.4), segment)
	t.check(shoulder > 0.0 and shoulder < 1.0, "road shoulder blends grip")
	t.eq(WorldRoads.coverage_on_segments(Vector2(15, 0), segment), 0.0,
		"the road does not extend past segment endpoints")
	t.eq(WorldRoads.coverage_on_segments(Vector2.INF, segment), 0.0,
		"invalid positions cannot grant road advantage")
	t.eq(WorldRoads.coverage_on_segments(Vector2.ZERO,
		[[Vector2.ZERO, Vector2.ZERO]]), 0.0, "degenerate pieces are ignored")
	t.current = "road driving and on-foot movement"
	var terrain := FakeRoad.new()
	var start := Vector3(0, 3, 0)
	var direction := {"x": 1.0}
	var foot_off: Vector3 = Movement.step(terrain, start, direction, 0.1)
	terrain.coverage_value = 1.0
	var foot_on: Vector3 = Movement.step(terrain, start, direction, 0.1)
	t.near(foot_on.x, foot_off.x * 1.08, 0.0001,
		"full road increases walking travel speed by exactly eight percent")
	t.eq(RoadTravel.foot_factor(terrain, start, true), 1.0,
		"crouch stealth is not accelerated")
	terrain.coverage_value = 0.0
	var bike_off: Vector3 = Movement.step(terrain, start,
		{"x": 1.0, "mounted": true}, 0.1)
	terrain.coverage_value = 1.0
	var bike_on: Vector3 = Movement.step(terrain, start,
		{"x": 1.0, "mounted": true}, 0.1)
	t.check(bike_on.x > bike_off.x, "dirt roads stabilize swamp bike riding")
	t.check(bike_on.x <= Defs.WALK_SPEED * Mounts.SPEED_FACTOR * \
		BikeTerrain.MAX_TRACTION * 0.1, "speed never exceeds bicycle cap")
	terrain.coverage_value = 0.5
	t.check(RoadTravel.bike_surface(0.56, 0.5) > 0.56 and \
			RoadTravel.bike_surface(0.56, 0.5) < RoadTravel.ROAD_BIKE_GRIP,
		"soft road shoulder has intermediate grip")
	terrain.coverage_value = INF
	t.eq(RoadTravel.coverage(terrain, start), 0.0,
		"nonfinite coverage grants no boost")
	terrain.coverage_value = 400.0
	t.eq(RoadTravel.coverage(terrain, start), 1.0, "oversized cover is clamped")
	t.near(RoadTravel.bike_surface(0.42, NAN), 0.42, 0.00001,
		"invalid road input preserves actual off-road grip")
	t.near(RoadTravel.bike_surface(0.42, INF), 0.42, 0.00001,
		"infinite road influence cannot give free speed")
	t.eq(RoadTravel.bike_surface(NAN, 0.7), 1.0,
		"unknown base surface retains safe legacy fallback")

	t.current = "real world links rendered roads and server controls"
	var world := WorldGen.new(1337)
	var found := false
	var spot := Vector3.ZERO
	for route in world.roads.all_roads():
		var points: PackedVector2Array = route["points"]
		for i in points.size() - 1:
			var mid: Vector2 = (points[i] + points[i + 1]) * 0.5
			if world.is_water(mid.x, mid.y) or not Movement._is_free(world, mid):
				continue
			if world.road_coverage_at(mid.x, mid.y) < 0.99:
				continue
			spot = Vector3(mid.x, world.height_at(mid.x, mid.y), mid.y)
			found = true
			break
		if found:
			break
	t.check(found, "a real road is physically traversable")
	if not found:
		return
	t.eq(RoadTravel.coverage(world, spot), 1.0,
		"road graphic and collision/travel use one seeded segment")
	t.eq(world.road_coverage_at(INF, 0.0), 0.0,
		"invalid road lookup cannot create bonus")
	var sim := GameServer.new(world, 1337)
	var rider = sim.add_player(811, "Road Rider")
	rider.position = spot
	rider.inventory.add(Mounts.ITEM_ID, 1)
	t.check(bool(sim.cmd_toggle_mount(811).get("mounted", false)),
		"legitimate rider can mount on road")
	var expected: Vector3 = Movement.step(world, spot,
		{"x": 1.0, "mounted": rider.mounted,
		"cargo_factor": rider.inventory.movement_factor(rider.skills.bonus("carry_capacity")),
		"injury_factor": 1.0, "speed_bonus": rider.skills.bonus("move_speed")}, 0.1)
	rider.input_budget = 0.1
	sim.submit_input(811, 1, 1.0, 0.0, false, 0.0, 0.1)
	t.near(rider.position.distance_to(expected), 0.0, 0.0001,
		"server uses same road physics as predictive movement")
	t.eq(sim.snapshot_for(811)["you"]["on_road"],
		RoadTravel.on_road(world, rider.position),
		"server snapshot identifies actual road contact")
