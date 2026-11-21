extends RefCounted
## Survivors swim and dive in deep water; infected and bikes cannot. Diving costs
## breath, drowning hurts, and sunken caches can only be opened underwater.
const Defs = preload("res://scripts/shared/defs.gd")
const Swimming = preload("res://scripts/shared/swimming.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


## A deep-water point (depth > 3 m) next to more deep water, outside safe zones.
static func deep_spot(world) -> Vector2:
	for ring in range(1, 60):
		for step in 24:
			var p := Vector2.from_angle(TAU * step / 24.0) * (ring * 40.0)
			if Swimming.depth_at(world, p.x, p.y) > 3.0 and Swimming.depth_at(world, p.x + 2.0, p.y) > 2.0 \
					and not world.is_safe(p.x, p.y):
				return p
	return Vector2.INF


func run(t) -> void:
	t.current = "breath and drowning"
	var air: Vector2 = Swimming.breathe(100.0, true, 1.0)
	t.near(air.x, 100.0 - Swimming.BREATH_DRAIN, 0.0001, "diving uses air")
	t.eq(air.y, 0.0, "no damage while air remains")
	t.near(Swimming.breathe(50.0, false, 1.0).x, 85.0, 0.0001, "surfacing refills air")
	var out: Vector2 = Swimming.breathe(0.0, true, 1.0)
	t.eq(out.x, 0.0, "no air left")
	t.near(out.y, Swimming.DROWN_DAMAGE, 0.0001, "drowning hurts")
	t.check(Swimming.breathe(Swimming.BREATH_DRAIN * 0.5, true, 1.0).y < Swimming.DROWN_DAMAGE, "only the airless part hurts")
	t.eq(Swimming.eel_chance(0, false, 1.0), 0.0, "no eels in green-zone water")
	t.eq(Swimming.eel_chance(3, true, 1.0), 0.0, "no eels in safe water")
	t.check(Swimming.eel_chance(2, false, 1.0) > Swimming.eel_chance(1, false, 1.0), "darker zones bite more")

	var world := WorldGen.new(1337)
	var spot := deep_spot(world)
	t.check(spot.is_finite(), "test world has deep water")
	if not spot.is_finite():
		return
	var start := Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)

	t.current = "survivors swim, bikes and infected do not"
	var swum: Vector3 = Movement.step(world, start, {"x": 1.0, "z": 0.0}, 0.1)
	t.check(Vector2(swum.x - start.x, swum.z - start.z).length() > 0.05, "a survivor swims through deep water")
	t.near(swum.y, Defs.WATER_LEVEL - Swimming.SURFACE_BODY, 0.0001, "swimmer floats at the surface")
	var still: Vector3 = Movement.step(world, start, {"x": 0.0, "z": 0.0}, 0.1)
	t.near(still.y, Defs.WATER_LEVEL - Swimming.SURFACE_BODY, 0.0001, "treading water keeps the head up")
	var dived: Vector3 = Movement.step(world, start, {"x": 0.0, "z": 0.0, "crouch": true}, 0.1)
	t.check(dived.y < swum.y - 1.0, "crouching dives under")
	t.check(dived.y >= world.height_at(dived.x, dived.z), "never below the bottom")
	var walk := Vector2(swum.x - start.x, swum.z - start.z).length() / 0.1
	t.check(walk < Defs.WALK_SPEED * 0.7, "swimming is slower than walking")
	var biked: Vector3 = Movement.step(world, start, {"x": 1.0, "z": 0.0, "mounted": true}, 0.1)
	t.check(Vector2(biked.x - start.x, biked.z - start.z).length() < 0.001, "bicycles cannot enter deep water")
	var zombie_move: Vector3 = Movement.move(world, start, Vector2(1, 0), 3.0, 0.1)
	t.check(Vector2(zombie_move.x - start.x, zombie_move.z - start.z).length() < 0.001, "infected still cannot swim")

	t.current = "server breath, drowning and eels"
	var sim := GameServer.new(world, 1337)
	var diver = sim.add_player(51, "Diver")
	diver.position = Vector3(spot.x, Swimming.body_y(world, spot.x, spot.y, true), spot.y)
	diver.crouching = true
	t.check(sim._is_diving(diver), "crouching swimmer counts as diving")
	sim._tick_underwater(diver, 2.0)
	t.near(diver.breath, 100.0 - Swimming.BREATH_DRAIN * 2.0, 0.0001, "server drains air")
	diver.breath = 0.0
	var health_before: float = diver.survival.health
	sim._tick_underwater(diver, 1.0)
	t.check(diver.survival.health < health_before, "out of air the diver drowns")
	diver.crouching = false
	sim._tick_underwater(diver, 1.0)
	t.check(diver.breath > 0.0, "surfacing gives air back")

	t.current = "sunken caches"
	var found: Dictionary = {}
	for ring in range(0, 40):
		for step in 16:
			var p := Vector2.from_angle(TAU * step / 16.0) * (ring * 64.0)
			for crate in world.chunk(WorldGen.cell_of(p.x, p.y))["crates"]:
				if bool(crate.get("sunken", false)):
					found = crate
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	t.check(not found.is_empty(), "the world hides sunken caches")
	if found.is_empty():
		return
	t.check(Swimming.depth_at(world, float(found["x"]), float(found["z"])) >= WorldGen.SUNKEN_MIN_DEPTH, "caches lie in deep water")
	var looter = sim.add_player(52, "Looter")
	looter.position = Vector3(float(found["x"]), Swimming.body_y(world, float(found["x"]), float(found["z"]), false), float(found["z"]))
	t.eq(sim.cmd_loot(52, int(found["id"])).get("reason", ""), "dive_to_reach", "a surface swimmer cannot reach the bottom")
	looter.crouching = true
	looter.position.y = Swimming.body_y(world, looter.position.x, looter.position.z, true)
	var result: Dictionary = sim.cmd_loot(52, int(found["id"]))
	t.check(bool(result.get("ok", false)) or str(result.get("reason", "")) == "inventory_full", "a diver opens the cache")
	t.check(bool(result.get("sunken", false)), "result marks the sunken cache")
