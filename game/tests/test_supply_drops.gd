extends RefCounted
## Regression coverage for timed server-authoritative public PvP supply crates.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const LootLabel = preload("res://scripts/shared/loot_label.gd")


class GridOnlyDangerWorld:
	extends RefCounted
	var center := Vector2(250.0, 200.0)
	var only_site := Vector2(238.0, 188.0)
	func zone_at(_x: float, _z: float) -> int:
		return 2
	func is_safe(_x: float, _z: float) -> bool:
		return false
	func is_water(x: float, z: float) -> bool:
		var p := Vector2(x, z)
		return p.distance_to(center) > 0.01 and p.distance_to(only_site) > 0.01
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP
	func height_at(_x: float, _z: float) -> float:
		return 3.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


class InvalidSupplyGround:
	extends RefCounted
	var safe: bool = false
	var normal_y: float = 1.0
	var elevation: float = 7.0

	func zone_at(_x: float, _z: float) -> int:
		return 2

	func is_safe(_x: float, _z: float) -> bool:
		return safe

	func is_water(_x: float, _z: float) -> bool:
		return false

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3(0.0, normal_y, 0.0)

	func height_at(_x: float, _z: float) -> float:
		return elevation

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return []


func run(t) -> void:
	t.current = "public drop and escort placement reject unsafe or corrupt terrain"
	var fake_ground := InvalidSupplyGround.new()
	var probe_rng := RandomNumberGenerator.new()
	probe_rng.seed = 101
	var probe := Vector3(300.0, 7.0, 300.0)
	t.check(not SupplyDrops.site_near(fake_ground, probe, probe_rng).is_empty(),
		"danger-zone supply drops accept stable dry ground")
	fake_ground.normal_y = NAN
	t.check(SupplyDrops.site_near(fake_ground, probe, probe_rng).is_empty(),
		"NaN ground normal cannot create a supply cache")
	t.eq(SupplyDrops.guard_sites(fake_ground,
		{"x": 300.0, "z": 300.0, "zone": 2}, [], {}, 1).size(), 0,
		"escorts cannot spawn on malformed terrain")
	fake_ground.normal_y = 1.0
	fake_ground.elevation = INF
	t.check(SupplyDrops.site_near(fake_ground, probe, probe_rng).is_empty(),
		"infinite elevation cannot create an unlootable cache")
	fake_ground.elevation = 7.0
	fake_ground.safe = true
	t.check(SupplyDrops.site_near(fake_ground, probe, probe_rng).is_empty(),
		"safe outposts cannot receive public PvP caches")

	t.current = "EQS oriented fallback grid for public cache guards"
	var test_center := Vector2(250.0, 200.0)
	var test_survivors: Array[Vector3] = [Vector3(250, 3, 190), Vector3(260, 3, 200)]
	var scripted_grid: PackedVector2Array = SupplyDrops.guard_grid_candidates(
		test_center, test_survivors, false)
	var native_grid: PackedVector2Array = SupplyDrops.guard_grid_candidates(
		test_center, test_survivors, true)
	t.eq(scripted_grid.size(), native_grid.size(),
		"native and portable oriented grid have the same eligible site count")
	t.check(scripted_grid.size() > 0 and scripted_grid.size() <= SupplyDrops.GUARD_GRID_SAMPLES,
		"guard backup candidate pool is strictly bounded")
	for i in scripted_grid.size():
		t.check(native_grid[i].distance_to(scripted_grid[i]) < 0.001,
			"native rotated grid agrees with portable coordinate generation")
		t.check(native_grid[i].distance_to(test_center) >= SupplyDrops.GUARD_RADII[0] - 0.001,
			"backup guards cannot spawn on top of the cache")
	t.eq(SupplyDrops.guard_grid_candidates(Vector2.INF, test_survivors).size(), 0,
		"nonfinite cache centers reject all grid generation")
	var only_grid_world := GridOnlyDangerWorld.new()
	var guarded: Array[Dictionary] = SupplyDrops.guard_sites(only_grid_world,
		{"x": 250.0, "z": 200.0, "zone": 2}, [], {}, 1)
	t.eq(guarded.size(), 1,
		"server selects a valid grid fallback when all 48 radial guard sites are blocked")
	if guarded.size() == 1:
		t.check(Vector2(float(guarded[0]["x"]), float(guarded[0]["z"])).distance_to(
			only_grid_world.only_site) < 0.001,
			"grid rescue location passes through the same terrain validation")
	only_grid_world.only_site = Vector2(250.0, 200.0)
	t.eq(SupplyDrops.guard_sites(only_grid_world,
		{"x": 250.0, "z": 200.0, "zone": 2}, [], {}, 1).size(), 0,
		"backup grid still refuses points inside the loot cache")

	t.current = "supply drop reward bounds"
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = 37
	var red_loot: Dictionary = SupplyDrops.loot_for_zone(2, loot_rng)
	t.eq(int(red_loot["silver"]), 120, "red zone pays a T3 supply reward")
	for id in red_loot:
		t.check(Defs.is_item(str(id)), "all supply contents exist in the item database: %s" % id)
		t.check(int(red_loot[id]) > 0 and int(red_loot[id]) <= Defs.stack_size(str(id)),
			"each reward fits a normal stack: %s" % id)
	var black_loot: Dictionary = SupplyDrops.loot_for_zone(3, loot_rng)
	t.check(black_loot.has("bar_4") and black_loot.has("cloth_4"),
		"black-zone supplies use T4 materials")

	t.current = "server time and safe zones"
	var world := WorldGen.new(17)
	var server := GameServer.new(world, 17)
	var player = server.add_player(93, "Supply Scout")
	server.time = SupplyDrops.INTERVAL_SECONDS
	server._tick_world(0.0)
	t.eq(server.bags.size(), 0, "no supply appears if everyone is in the safe hub")
	t.eq(server.next_supply_drop_at, SupplyDrops.INTERVAL_SECONDS + SupplyDrops.RETRY_SECONDS,
		"empty-server attempt backs off instead of spawning a free cache")
	t.eq(SupplyDrops.site_near(world, player.position, loot_rng).size(), 0,
		"site selection refuses the safe hub")

	var anchor := Vector2.ZERO
	for i in 72:
		var candidate := Vector2.from_angle(float(i) * TAU / 72.0) * 800.0
		if not world.is_water(candidate.x, candidate.y) and world.normal_at(candidate.x, candidate.y).y > 0.85:
			anchor = candidate
			break
	t.check(anchor != Vector2.ZERO, "a traversable red-zone test site exists")
	if anchor == Vector2.ZERO:
		return
	player.position = Vector3(anchor.x, world.height_at(anchor.x, anchor.y), anchor.y)
	server.time = server.next_supply_drop_at - 0.01
	server._tick_world(0.0)
	t.eq(server.bags.size(), 0, "a supply cannot spawn before its deadline")
	server.time = server.next_supply_drop_at
	server._tick_world(0.0)
	t.eq(server.bags.size(), 1, "one public cache spawns for an eligible survivor")
	if server.bags.is_empty():
		return
	var bag_id: int = int(server.bags.keys()[0])
	var bag: Dictionary = server.bags[bag_id]
	t.check(bool(bag.get("supply_drop", false)), "the drop is marked for clients")
	t.check(not bag.has("allowed_tokens"), "the drop is public, not party-reserved")
	t.eq(world.zone_at(float(bag["x"]), float(bag["z"])), 2,
		"loot lands in the red PvP zone")
	var distance: float = Vector2(player.position.x, player.position.z).distance_to(
		Vector2(float(bag["x"]), float(bag["z"])))
	t.check(distance >= SupplyDrops.MIN_DISTANCE and distance <= SupplyDrops.MAX_DISTANCE + 0.01,
		"cache arrives within the player's nearby visibility radius")
	t.eq(float(bag["expires"]), server.time + SupplyDrops.LIFETIME_SECONDS,
		"public cache expires after a bounded interval")
	var view: Dictionary = server.snapshot_for(93)
	var found := false
	var visible_guards := 0
	for visible in view["bags"]:
		if int(visible["id"]) == bag_id:
			found = bool(visible.get("supply_drop", false))
			visible_guards = int(visible.get("guards_remaining", 0))
			t.eq(bool(visible["can_loot"]), visible_guards == 0,
				"cache is locked only while its original guards survive")
	t.check(found, "nearby clients see a clearly marked supply crate")
	t.eq(visible_guards, SupplyDrops.living_guards(bag, server.zombies),
		"snapshot guard count is server-authoritative")
	t.eq(LootLabel.for_bag({"supply_drop": true}), "SUPPLY DROP - public",
		"the world label distinguishes supply from ordinary death loot")

	var announced := false
	for event in server.drain_events():
		if event.get("type", "") == "supply_drop":
			announced = int(event.get("id", -1)) == bag_id
	t.check(announced, "a world announcement is emitted after server creation")

	player.position = Vector3(float(bag["x"]), float(bag["y"]), float(bag["z"]))
	# The existing world objective requires defeating the escort first.
	if visible_guards > 0:
		t.eq(server.cmd_loot(93, bag_id).get("reason"), "guards_alive",
			"attempting to loot a guarded crate is denied")
	for id in bag.get("supply_guard_ids", []):
		var infected = server.zombies.get(int(id))
		if infected != null:
			infected.take_damage(100000.0)
	var result: Dictionary = server.cmd_loot(93, bag_id)
	t.check(bool(result.get("ok", false)), "the legitimate nearby player can loot it")
	t.check(not server.bags.has(bag_id), "a fully looted supply cache is removed")
	t.check(player.inventory.count("silver") >= 120, "supply was actually transferred")
	server._tick_world(0.0)
	t.eq(server.bags.size(), 0, "checking the same tick cannot duplicate the reward")
