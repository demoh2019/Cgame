extends RefCounted
## Walls face the way they were placed (snapped to eighths), keep while their owner comes by, crumble when left alone
## past their upkeep, and carry facing and upkeep through a server restart.

const Structures = preload("res://scripts/shared/structures.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")


func _site(world) -> Vector2:
	for x in range(60, 400, 6):
		for z in range(60, 400, 6):
			if Structures.placement_reason(world, Vector2(x, z), Vector2(x - 3.0, z)) == "":
				return Vector2(x, z)
	return Vector2.INF


func run(t) -> void:
	t.current = "facing snaps to eighths of a circle"
	t.near(Structures.snap_yaw(0.8), PI / 4.0, 0.0001, "0.8 rad snaps to 45 degrees")
	t.near(Structures.snap_yaw(-PI / 2.0), PI * 1.5, 0.0001, "negative angles wrap")
	t.eq(Structures.snap_yaw(NAN), 0.0, "nonsense faces north")

	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var builder = sim.add_player(7, "Builder", "builder-account")
	var spot: Vector2 = _site(world)
	t.check(spot.is_finite(), "a buildable spot exists")
	if not spot.is_finite():
		return
	builder.position = Vector3(spot.x - 3.0, world.height_at(spot.x - 3.0, spot.y), spot.y)
	builder.inventory.add("wood_1", 10)
	builder.inventory.add("stone_1", 10)

	t.current = "placement uses the shared rules and stores the facing"
	t.eq(Structures.placement_reason(world, Vector2(5, 5), Vector2(3, 5)), "out_of_range" if Vector2(5, 5).distance_to(Vector2(3, 5)) < Structures.MIN_BUILD_DISTANCE else "safe_zone", "the hub refuses walls")
	var built: Dictionary = sim.cmd_build(7, spot.x, spot.y, 1.6)
	t.check(bool(built.get("ok", false)), "built")
	if not bool(built.get("ok", false)):
		return
	var id: int = int(built["id"])
	t.near(float(sim.barricades[id]["yaw"]), PI / 2.0, 0.0001, "stored facing is snapped")
	t.near(float(Structures.public_state(sim.barricades[id])["yaw"]), PI / 2.0, 0.0001, "and shown to everyone")

	t.current = "an owner nearby keeps the wall; left alone it crumbles"
	sim.barricades[id]["upkeep_until"] = sim.time - 1.0
	sim._tick_barricade_upkeep(60.0)
	t.check(float(sim.barricades[id]["upkeep_until"]) > sim.time, "the owner standing by renews the upkeep")
	t.near(float(sim.barricades[id]["hp"]), Structures.MAX_HEALTH, 0.0001, "and nothing decays")
	builder.position = Vector3(spot.x + 200.0, 0.0, spot.y)
	sim.barricades[id]["upkeep_until"] = sim.time - 1.0
	sim._tick_barricade_upkeep(600.0)
	t.check(float(sim.barricades[id]["hp"]) < Structures.MAX_HEALTH, "an abandoned wall loses health")
	sim._tick_barricade_upkeep(Structures.DECAY_SECONDS)
	t.check(not sim.barricades.has(id), "and is gone at zero")
	t.check(not sim.events.filter(func(e: Dictionary) -> bool: return e["type"] == "barricade_decayed").is_empty(), "the crumble is announced")

	t.current = "facing and upkeep survive a restart; older checkpoints still load"
	builder.position = Vector3(spot.x - 3.0, world.height_at(spot.x - 3.0, spot.y), spot.y)
	var again: Dictionary = sim.cmd_build(7, spot.x, spot.y, PI / 4.0)
	t.check(bool(again.get("ok", false)), "rebuilt")
	var checkpoint: Dictionary = WorldPersistence.capture(sim)
	t.near(float(checkpoint["barricades"][0]["yaw"]), PI / 4.0, 0.0001, "facing saved")
	t.check(float(checkpoint["barricades"][0]["upkeep"]) > 0.0, "upkeep saved")
	var reboot := GameServer.new(WorldGen.new(214), 215)
	t.check(WorldPersistence.restore(reboot, JSON.parse_string(JSON.stringify(checkpoint))), "restored")
	var restored: Dictionary = reboot.barricades.values()[0] if not reboot.barricades.is_empty() else {}
	t.near(float(restored.get("yaw", -1.0)), PI / 4.0, 0.0001, "restored facing")
	t.check(float(restored.get("upkeep_until", 0.0)) > reboot.time, "restored upkeep")
	var forged: Dictionary = checkpoint.duplicate(true)
	forged["barricades"][0]["upkeep"] = Structures.UPKEEP_SECONDS * 10.0
	t.check(WorldPersistence.validate(forged, GameServer.new(WorldGen.new(214), 216)).is_empty(), "endless upkeep is refused")
