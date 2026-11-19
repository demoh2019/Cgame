extends RefCounted
## Server-only regression: night base sieges use actual collision, AI target
## rules, structure ownership/range and bounded zombie population.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const SiegeWaves = preload("res://scripts/shared/siege_waves.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const BarricadeTests = preload("res://tests/test_barricades.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _count_events(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if event.get("type") == event_type:
			count += 1
	return count


func run(t) -> void:
	var world := WorldGen.new(214)
	var server = GameServer.new(world, 314)
	var site: Vector2 = BarricadeTests.new()._find_place(world)
	t.current = "night siege rules and bounded spawn locations"
	t.check(site != Vector2.ZERO, "found a legitimate base location outside the settlement")
	if site == Vector2.ZERO:
		return
	t.eq(SiegeWaves.wave_size(1), 2, "T1 walls attract two infected")
	t.eq(SiegeWaves.wave_size(2), 3, "T2 defenses attract three infected")
	t.eq(SiegeWaves.wave_size(4), 5, "T4 defenses attract at most five infected")
	t.check(not SiegeWaves.eligible({"x": 9.0, "z": 0.0}, Vector3(9, 0, 0), 675.0), "protected hub is never a siege target")
	var p = server.add_player(71, "Builder", "account-defender")
	var origin := site + Vector2(-2.8, 0.0)
	p.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	p.inventory.add("wood_1", 4)
	p.inventory.add("stone_1", 2)
	var built: Dictionary = server.cmd_build(71, site.x, site.y)
	t.check(built.get("ok", false), "owner builds a real T1 base before the attack")
	if not built.get("ok", false):
		return
	var id: int = int(built["id"])
	var wall: Dictionary = server.barricades[id]
	var sites: Array[Vector2] = SiegeWaves.spawn_sites(world, wall, p.position, 2)
	t.check(sites.size() > 0, "siege director finds passable enemy entry positions")
	for point in sites:
		t.check(Movement._is_free(world, point), "siege site has no physics blocker")
		t.check(point.length() >= Structures.MIN_HUB_DISTANCE, "siege never spawns inside safe settlement")
		t.check(point.distance_to(Vector2(p.position.x, p.position.z)) >= SiegeWaves.MIN_PLAYER_SPAWN_DISTANCE,
			"infected do not materialize beside player")
		t.check(point.distance_to(Vector2(p.position.x, p.position.z)) <= SiegeWaves.MAX_PLAYER_SPAWN_DISTANCE,
			"infected spawn within pursuit leash")
	server.time = WorldCycle.DAY_LENGTH * 0.25
	t.check(not SiegeWaves.eligible(wall, p.position, server.time), "daylight prevents wave eligibility")
	server._tick_siege_waves()
	t.eq(server.siege_waves_started, 0, "no horde is launched during the day")
	t.eq(server.zombies.size(), 0, "daylight does not create infected")

	t.current = "authoritative T1 siege and player alert"
	server.time = WorldCycle.DAY_LENGTH * 0.75
	t.check(SiegeWaves.eligible(wall, p.position, server.time), "survivor near wall is an eligible night target")
	server._tick_siege_waves()
	t.eq(server.siege_waves_started, 1, "one nighttime siege was launched")
	t.check(server.zombies.size() > 0 and server.zombies.size() <= 2, "wave is strictly bounded by tier")
	t.eq(_count_events(server.events, "siege_started"), 1, "one public siege notification emitted")
	t.eq(int(server.siege_last_by_wall[id]), int(server.time), "wall cooldown recorded by server")
	for enemy in server.zombies.values():
		t.eq(enemy.target_id, p.id, "siege enemies acquire live defender")
		t.eq(enemy.state, Zombie.State.CHASE, "spawned infected enter pursuit")
		t.check(Vector2(enemy.position.x, enemy.position.z).distance_to(site) <= 24.1,
			"all attackers are near the defended structure")
	var first_count: int = server.zombies.size()
	server._tick_siege_waves()
	t.eq(server.zombies.size(), first_count, "repeated scheduler call cannot spam attackers")
	server.time += SiegeWaves.GLOBAL_COOLDOWN + 1.0
	server._tick_siege_waves()
	t.eq(server.siege_waves_started, 1, "per-wall cooldown still blocks another wave")
	t.eq(server.zombies.size(), first_count, "cooldown rejects repeated spawning")

	t.current = "strong walls, active cap and daylight controls"
	server.barricades[id]["tier"] = 4 # Trusted test setup, never an RPC
	server.barricades[id]["hp"] = Structures.max_health(4)
	server.time += SiegeWaves.WALL_COOLDOWN + 1.0
	server._tick_siege_waves()
	t.eq(server.siege_waves_started, 2, "another raid is possible after cooldown")
	var second_count: int = server.zombies.size()
	t.check(second_count > first_count and second_count <= first_count + SiegeWaves.wave_size(4),
		"T4 attack is larger but still bounded")
	var event_count: int = _count_events(server.events, "siege_started")
	t.eq(event_count, 2, "only two distinct siege events")
	server.time = WorldCycle.DAY_LENGTH * 2.0 + WorldCycle.DAY_LENGTH * 0.25
	server._tick_siege_waves()
	t.eq(server.siege_waves_started, 2, "daytime stops all new sieges regardless of elapsed cooldown")

	t.current = "safe settlement, offline defenses and hard server population cap"
	server.time = WorldCycle.DAY_LENGTH * 2.0 + WorldCycle.DAY_LENGTH * 0.75
	p.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	server._tick_siege_waves()
	t.eq(server.siege_waves_started, 2, "safe-zone player does not trigger a remote horde")
	p.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	# Fill the active cap with existing server-owned infected; never create 91st.
	for index in range(SiegeWaves.MAX_ACTIVE_ZOMBIES - server.zombies.size()):
		var enemy_id: int = server.new_id()
		server.zombies[enemy_id] = Zombie.new(enemy_id, "walker",
			Vector3(site.x + 2.0, world.height_at(site.x + 2.0, site.y), site.y), -1)
	t.eq(server.zombies.size(), SiegeWaves.MAX_ACTIVE_ZOMBIES, "test fills global population budget exactly")
	server._tick_siege_waves()
	t.eq(server.zombies.size(), SiegeWaves.MAX_ACTIVE_ZOMBIES, "global cap refuses any additional enemy")
	t.eq(server.siege_waves_started, 2, "population cap does not consume wave cooldown")
	t.check(server.damage_barricade(id, 10000.0), "server can destroy a defended wall")
	t.check(not server.siege_last_by_wall.has(id), "destruction cleans up event timers")
	server.zombies.clear()
	server._tick_siege_waves()
	t.eq(server.zombies.size(), 0, "destroyed base cannot trigger another siege")

	t.current = "no client-visible privileged structure data"
	t.eq(server.snapshot_for(71)["barricades"].size(), 0, "destroyed wall absent from replicated snapshots")
	t.check(_count_events(server.events, "siege_started") == 2, "notifications remain bounded and do not leak server state")
