extends RefCounted
## Real combat-only completion for timed dangerous-zone night hordes.
const NightHorde = preload("res://scripts/shared/night_horde.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")
const LootLabel = preload("res://scripts/shared/loot_label.gd")
const Defs = preload("res://scripts/shared/defs.gd")


class FlatDanger:
	extends RefCounted
	var blocked: bool = false

	func zone_at(_x: float, _z: float) -> int:
		return 2

	func is_safe(_x: float, _z: float) -> bool:
		return false

	func is_water(_x: float, _z: float) -> bool:
		return false

	func height_at(_x: float, _z: float) -> float:
		return 0.0

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return [{"x": 0.0, "z": 0.0, "radius": 2000.0}] if blocked else []


class ScatterOnlyDanger:
	extends RefCounted
	var center := Vector2(230.0, 180.0)
	var only_site := Vector2.INF
	func zone_at(_x: float, _z: float) -> int:
		return 2
	func is_safe(_x: float, _z: float) -> bool:
		return false
	func is_water(x: float, z: float) -> bool:
		var point := Vector2(x, z)
		return point.distance_to(center) > 0.001 and \
			point.distance_to(only_site) > 0.001
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP
	func height_at(_x: float, _z: float) -> float:
		return 10.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


func _site(world) -> Vector3:
	for i in 96:
		var point := Vector2.from_angle(TAU * float(i) / 96.0) * 800.0
		if world.zone_at(point.x, point.y) == 2 and not world.is_water(
				point.x, point.y) and world.normal_at(point.x, point.y).y > 0.8:
			return Vector3(point.x, world.height_at(point.x, point.y), point.y)
	return Vector3.INF


func run(t) -> void:
	t.current = "native area-uniform scatter for night horde fallback"
	var scatter_center := Vector2(230.0, 180.0)
	for phase_offset in [0, 5, -3]:
		var script_points := NightHorde.scatter_candidates(scatter_center, phase_offset, false)
		var native_points := NightHorde.scatter_candidates(scatter_center, phase_offset, true)
		t.eq(script_points.size(), NightHorde.SCATTER_COUNT,
			"stock Godot keeps the bounded radial scatter candidate budget")
		t.eq(native_points.size(), script_points.size(),
			"native and portable radial scatter have identical candidate counts")
		for index in script_points.size():
			t.check(native_points[index].distance_to(script_points[index]) < 0.001,
				"native Fibonacci scatter preserves portable candidate positions and order")
			var r: float = native_points[index].distance_to(scatter_center)
			t.check(r >= float(NightHorde.RADII[0]) - 0.001 and \
				r <= float(NightHorde.RADII[-1]) + 0.001,
				"scatter points remain within the existing night horde radial bounds")
	t.eq(NightHorde.scatter_candidates(Vector2.INF).size(), 0,
		"invalid incident center cannot generate unsafe positions")
	var isolated := ScatterOnlyDanger.new()
	isolated.only_site = NightHorde.scatter_candidates(isolated.center, 0, false)[0]
	var rescue := NightHorde.sites(isolated,
		Vector3(isolated.center.x, 10, isolated.center.y), [], {}, 3)
	t.eq(rescue.size(), 1,
		"authoritative night horde finds a valid area-uniform scatter site after every ring fails")
	if rescue.size() == 1:
		t.check(Vector2(float(rescue[0]["x"]), float(rescue[0]["z"])).distance_to(
			isolated.only_site) < 0.001,
			"native/portable scatter site passes the exact same server terrain checks")
	isolated.only_site = Vector2.INF
	t.check(NightHorde.sites(isolated,
		Vector3(isolated.center.x, 10, isolated.center.y), [], {}, 3).is_empty(),
		"scatter is also rejected when no terrain is walkable")

	t.current = "real rewards and bounded terrain-safe enemy compositions"
	t.eq(NightHorde.kinds(2), ["runner", "walker", "runner"],
		"red zone sends three recognizable infected")
	t.eq(NightHorde.kinds(3), ["runner", "brute", "spitter", "runner"],
		"black zone adds a special brute and spitter")
	t.check(NightHorde.kinds(1).is_empty(), "low-risk zones have no horde encounter")
	for zone in [2, 3]:
		for item in NightHorde.loot(zone):
			t.check(Defs.is_item(str(item)) and int(NightHorde.loot(zone)[item]) > 0,
				"rewards are valid server-side inventory items")
	t.eq(NightHorde.loot(1), {}, "protected zones cannot mint special trophies")
	t.check(not NightHorde.fully_defeated([], {}),
		"empty encounter cannot grant reward")
	var ground := FlatDanger.new()
	var point := Vector3(230.0, 0, 180.0)
	var survivors: Array[Vector3] = [point]
	var placements: Array[Dictionary] = NightHorde.sites(
		ground, point, survivors, {}, 4)
	t.eq(placements.size(), 3, "all spawned enemies fit in a bounded red wave")
	for spot in placements:
		var at := Vector2(float(spot["x"]), float(spot["z"]))
		t.check(at.distance_to(Vector2(point.x, point.z)) >= NightHorde.MIN_PLAYER_SEPARATION,
			"spawn never overlaps survivor")
	t.eq(NightHorde.sites(ground, point, survivors, {}, 1).size(), 1,
		"capacity prevents zombie overload")
	t.check(NightHorde.sites(ground, Vector3.INF, survivors, {}, 3).is_empty(),
		"invalid survivor position is rejected")
	ground.blocked = true
	t.check(NightHorde.sites(ground, point, survivors, {}, 3).is_empty(),
		"solid walls prevent event spawning")

	t.current = "night-only automatic spawns with no client action"
	var world := WorldGen.new(171)
	var sim := GameServer.new(world, 171)
	var hunter = sim.add_player(401, "Horde Hunter")
	var watcher = sim.add_player(402, "Nearby Rival")
	var distant = sim.add_player(403, "Hub Watcher")
	var center: Vector3 = _site(world)
	t.check(center.is_finite(), "find walkable red-zone encounter")
	if not center.is_finite():
		return
	hunter.position = center
	watcher.position = center + Vector3(4, 0, 0)
	distant.position = Vector3(0, world.height_at(0, 0), 0)
	sim.tick_count = NightHorde.CHECK_EVERY_TICKS
	sim.time = NightHorde.START_DELAY - 1.0
	sim._tick_night_horde()
	t.check(sim.night_horde.is_empty(), "before delay no wave can spawn")
	sim.time = NightHorde.START_DELAY
	t.check(WorldCycle.is_night(sim.time), "scheduled first horde is at night")
	sim._tick_night_horde()
	t.check(not sim.night_horde.is_empty(), "server created a real wave")
	if sim.night_horde.is_empty():
		return
	var member_ids: Array = sim.night_horde["ids"]
	t.check(member_ids.size() >= 2 and member_ids.size() <= 4,
		"actual enemy wave is bounded, no trivial lone cache")
	for id in member_ids:
		var enemy = sim.zombies[int(id)]
		t.eq(enemy.spawn_id, -1, "event enemies do not own global spawn slots")
		t.check(not enemy.elite and not enemy.raid_boss,
			"event enemies do not copy raid/elite rewards")
	sim.drain_events()
	var first_id: int = int(member_ids[0])
	var first = sim.zombies[first_id]
	first.take_damage(100000.0)
	sim._on_zombie_death(first, hunter)
	t.check(not NightHorde.fully_defeated(member_ids, sim.zombies),
		"partial victory does not count as full completion")
	t.check(not sim.night_horde.is_empty(), "event remains active after first kill")
	t.eq(sim.bags.values().filter(func(b): return b.get("horde_cache", false)).size(), 0,
		"one enemy never grants group chest")
	for index in range(1, member_ids.size()):
		var enemy = sim.zombies[int(member_ids[index])]
		enemy.take_damage(100000.0)
		sim._on_zombie_death(enemy, hunter)
	t.check(sim.night_horde.is_empty(), "final confirmed kill closes the encounter")
	var chests: Array = sim.bags.values().filter(func(b): return b.get("horde_cache", false))
	t.eq(chests.size(), 1, "only one public reward spawned")
	if chests.is_empty():
		return
	var prize: Dictionary = chests[0]
	t.eq(prize.get("items", {}), NightHorde.loot(2), "trophy is a fixed bounded red-zone reward")
	t.eq(LootLabel.for_bag({"horde_cache": true}), "HORDE TROPHY - public",
		"3D world label marks public objective")
	var events: Array = sim.drain_events()
	var completion: int = 0
	var notice: Dictionary = {}
	for event in events:
		if event.get("type") == "horde_cleared":
			completion += 1
			notice = event
	t.eq(completion, 1, "one server-only completion announcement")
	t.check(not notice.has("killer") and not notice.has("peer"),
		"public prize event cannot leak hunter identity")
	var network := Net.new()
	network.role = "server"
	network.sim = sim
	t.check(network._event_visible_to(notice, 401), "hunter sees local trophy")
	t.check(network._event_visible_to(notice, 402), "nearby rival sees PvP trophy")
	t.check(not network._event_visible_to(notice, 403), "distant hub is not tracked")
	network.free()
	var snap: Dictionary = sim.snapshot_for(401)
	var visible: bool = false
	for bag in snap["bags"]:
		if int(bag["id"]) == int(prize["id"]):
			visible = bool(bag.get("horde_cache", false))
	t.check(visible, "actual public chest reaches client snapshot")
	hunter.position = Vector3(float(prize["x"]), float(prize["y"]), float(prize["z"]))
	t.check(bool(sim.cmd_loot(401, int(prize["id"])).get("ok", false)),
		"public trophy can be looted using existing bag command")
	t.check(not sim.bags.has(int(prize["id"])), "public reward cannot be collected twice")

	t.current = "missing combat confirmations cannot create a prize"
	var zombie = Zombie.new(sim.new_id(), "walker", center, -1)
	sim.zombies[zombie.id] = zombie
	sim.night_horde = {"ids": [zombie.id, 999999], "zone": 2,
		"x": center.x, "z": center.z, "expires": sim.time + 100.0}
	zombie.take_damage(100000.0)
	sim._on_zombie_death(zombie, hunter)
	t.check(not sim.night_horde.is_empty(), "lost horde member prevents completion")
	t.check(not NightHorde.fully_defeated(sim.night_horde["ids"], sim.zombies),
		"missing ID is not treated as a kill")
	sim.time += 101.0
	sim._tick_night_horde()
	t.check(sim.night_horde.is_empty(), "expired horde is cleaned up")
	t.eq(sim.bags.values().filter(func(b): return b.get("horde_cache", false)).size(), 0,
		"expiration never grants bonus loot")
