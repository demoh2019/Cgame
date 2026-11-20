extends RefCounted
## Public red/black-zone supply drops receive bounded, legitimate zombie escorts.

const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


class FlatDangerWorld:
	extends RefCounted
	var blocked: bool = false

	func zone_at(_x: float, _z: float) -> int:
		return 2

	func is_safe(_x: float, _z: float) -> bool:
		return false

	func is_water(_x: float, _z: float) -> bool:
		return false

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP

	func height_at(_x: float, _z: float) -> float:
		return 2.0

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return [{"x": 0.0, "z": 0.0, "radius": 1000.0}] if blocked else []


func run(t) -> void:
	t.current = "risk-dependent bounded escort tiers"
	t.eq(SupplyDrops.guard_types(1).size(), 0, "safe and yellow zones have no guards")
	t.eq(SupplyDrops.guard_types(2), ["walker", "runner"],
		"red PvP supplies have two infected escorts")
	t.eq(SupplyDrops.guard_types(3), ["runner", "walker", "brute"],
		"black PvP supplies introduce a brute")

	var flat := FlatDangerWorld.new()
	var site := {"x": 250.0, "z": 200.0, "zone": 2}
	var nobody: Array[Vector3] = []
	t.current = "dry, collision-free, spaced patrol sites"
	var result: Array[Dictionary] = SupplyDrops.guard_sites(flat, site, nobody, {}, 3)
	t.eq(result.size(), 2, "red tier cannot exceed two guards")
	for guard in result:
		var p := Vector2(float(guard["x"]), float(guard["z"]))
		var distance: float = p.distance_to(Vector2(250, 200))
		t.check(distance >= SupplyDrops.GUARD_RADII[0] - 0.001 and
			distance <= SupplyDrops.GUARD_RADII.back() + 0.001,
			"escort stays within bounded ring")
		t.check(str(guard["kind"]) in ["walker", "runner"], "guard type is legitimate")
	t.eq(SupplyDrops.guard_sites(flat, site, nobody, {}, 1).size(), 1,
		"global infected capacity also limits escorts")
	t.check(SupplyDrops.guard_sites(flat, site, nobody, {}, 0).is_empty(),
		"zero capacity cannot create guards")
	t.check(SupplyDrops.guard_sites(flat, {"x": NAN, "z": 0, "zone": 2},
		nobody, {}, 3).is_empty(), "invalid drop coordinate rejected")
	t.check(SupplyDrops.guard_sites(flat, {"x": 250, "z": 200, "zone": 1},
		nobody, {}, 3).is_empty(), "client-forged zone cannot mint guards")
	flat.blocked = true
	t.check(SupplyDrops.guard_sites(flat, site, nobody, {}, 3).is_empty(),
		"solid obstacle stops escort spawns")
	flat.blocked = false
	var covered: Array[Vector3] = []
	for ring in SupplyDrops.GUARD_RADII:
		for index in SupplyDrops.GUARD_ANGLES:
			var at: Vector2 = Vector2(250, 200) + Vector2.from_angle(
				TAU * float(index) / float(SupplyDrops.GUARD_ANGLES)) * float(ring)
			covered.append(Vector3(at.x, 2, at.y))
	t.check(SupplyDrops.guard_sites(flat, site, covered, {}, 3).is_empty(),
		"never materialize escorts right beside survivors")

	t.current = "real server-owned infected lifecycle"
	var world := WorldGen.new(17)
	var sim := GameServer.new(world, 17)
	var player = sim.add_player(93, "Drop Runner")
	var anchor := Vector2.ZERO
	for i in 72:
		var candidate := Vector2.from_angle(float(i) * TAU / 72.0) * 800.0
		if not world.is_water(candidate.x, candidate.y) and world.normal_at(
				candidate.x, candidate.y).y > 0.85:
			anchor = candidate
			break
	t.check(anchor != Vector2.ZERO, "find actual red-zone survivor")
	if anchor == Vector2.ZERO:
		return
	player.position = Vector3(anchor.x, world.height_at(anchor.x, anchor.y), anchor.y)
	sim.time = SupplyDrops.INTERVAL_SECONDS
	sim._tick_world(0.0)
	t.eq(sim.bags.size(), 1, "one public supply cache on server")
	if sim.bags.is_empty():
		return
	var bag: Dictionary = sim.bags.values()[0]
	t.check(bool(bag.get("supply_drop", false)), "ordinary public bag still exists")
	var guard_count: int = 0
	for event in sim.drain_events():
		if event.get("type", "") == "supply_drop":
			guard_count = int(event.get("guards", -1))
	t.check(guard_count >= 0 and guard_count <= SupplyDrops.MAX_GUARDS,
		"announcement reports bounded server-generated escort count")
	t.eq(sim.zombies.size(), guard_count, "only announced guards were spawned")
	for enemy in sim.zombies.values():
		t.eq(enemy.spawn_id, -1, "escort has no renewable world spawn slot")
		t.check(not enemy.elite and not enemy.raid_boss,
			"escort cannot create bonus elite or raid rewards")
		var spot := Vector2(enemy.position.x, enemy.position.z)
		t.check(spot.distance_to(Vector2(player.position.x, player.position.z)) >=
			SupplyDrops.MIN_SURVIVOR_DISTANCE - 0.01,
			"no escort spawns directly onto a survivor")
		t.eq(world.zone_at(spot.x, spot.y), 2, "escorts stay inside same risk zone")
	t.eq(sim._spawn_supply_guards({"x": NAN, "z": 0.0, "zone": 2}), 0,
		"invalid server drop site cannot create additional escorts")
	t.eq(sim.zombies.size(), guard_count, "invalid attempt creates no zombies")
