extends RefCounted
## Two server-owned raid phases, safe spawns, bounded adds and cleanup.
const RaidReinforcements = preload("res://scripts/shared/raid_reinforcements.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


class FlatWorld:
	extends RefCounted
	var world_seed: int = 721
	func zone_at(x: float, _z: float) -> int:
		return 2 if x > 100.0 else 0
	func is_safe(x: float, _z: float) -> bool:
		return x <= 100.0
	func is_water(_x: float, _z: float) -> bool:
		return false
	func height_at(_x: float, _z: float) -> float:
		return 3.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


func at(x: float, z: float) -> Vector3:
	return Vector3(x, 3.0, z)


func run(t) -> void:
	t.current = "finite health thresholds and no phase replay"
	t.eq(RaidReinforcements.next_phase(600.0, 600.0, 0), 0, "full HP is idle")
	t.eq(RaidReinforcements.next_phase(390.0, 600.0, 0), 1, "65% triggers phase 1")
	t.eq(RaidReinforcements.next_phase(300.0, 600.0, 1), 0, "phase 2 is not premature")
	t.eq(RaidReinforcements.next_phase(180.0, 600.0, 1), 2, "30% triggers phase 2")
	t.eq(RaidReinforcements.next_phase(100.0, 600.0, 2), 0, "completed phases do not replay")
	t.eq(RaidReinforcements.next_phase(0.0, 600.0, 0), 0, "dead boss summons nobody")
	t.eq(RaidReinforcements.next_phase(NAN, 600.0, 0), 0, "NaN cannot summon")
	t.eq(RaidReinforcements.kinds(2).size(), 2, "final wave is bounded")

	t.current = "server only, genuine infected, safe coordinates"
	var world := FlatWorld.new()
	var server := GameServer.new(world, 721)
	var fighter = server.add_player(301, "Frontline")
	var ally = server.add_player(302, "Archer")
	fighter.position = at(200.0, 200.0)
	ally.position = at(202.0, 202.0)
	var boss_id: int = server.new_id()
	var boss := Zombie.new(boss_id, "brute", at(215.0, 200.0), -1)
	RaidEncounter.empower(boss)
	boss.target_id = fighter.id
	server.zombies[boss_id] = boss
	server.raid_boss_id = boss_id
	server.raid_started_at = 100.0
	server.raid_next_slam_at = 1000.0
	server.time = 120.0
	t.eq(RaidReinforcements.sites(world, server.players, server.zombies,
		at(50.0, 200.0), 1, 2).size(), 0, "safe hub blocks adds")
	var sites := RaidReinforcements.sites(world, server.players,
		server.zombies, boss.position, 1, 2)
	t.eq(sites.size(), 2, "clear dangerous terrain permits two adds")
	for site in sites:
		t.eq(world.zone_at(site.x, site.y), 2, "adds stay in encounter zone")
		t.check(site.distance_to(Vector2(fighter.position.x, fighter.position.z))
			>= RaidReinforcements.MIN_PLAYER_DISTANCE, "adds cannot spawn onto players")
	boss.health = 390.0
	server._tick_raid_encounter()
	t.eq(server.raid_wave, 1, "server starts phase 1 from actual boss health")
	t.eq(server.raid_minions.size(), 2, "first phase creates exactly two minions")
	t.eq(server.zombies.size(), 3, "boss remains active with reinforcements")
	server._tick_raid_encounter()
	t.eq(server.raid_minions.size(), 2, "repeat tick cannot farm additional spawns")
	var alerts: Array = server.events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "raid_reinforcements")
	t.eq(alerts.size(), 1, "phase notification appears once")
	var conn := Net.new()
	conn.role = "server"
	conn.sim = server
	t.check(conn._event_visible_to(alerts[0], fighter.id), "nearby group sees event")
	var remote = server.add_player(303, "Remote")
	remote.position = at(0, 0)
	t.check(not conn._event_visible_to(alerts[0], remote.id),
		"remote players do not receive raid locations")
	conn.free()
	boss.health = 180.0
	server._tick_raid_encounter()
	t.eq(server.raid_wave, 2, "final phase starts at low HP")
	t.eq(server.raid_minions.size(), 4, "only four minions total")
	var has_brute := false
	for id in server.raid_minions:
		if server.zombies[id].type == "brute":
			has_brute = true
	t.check(has_brute, "second wave adds a brute")
	var old_minions: Array = server.raid_minions.duplicate()
	server._damage_target(fighter, {"kind": "zombie", "id": boss_id}, 2000.0)
	t.eq(server.raid_boss_id, -1, "victory releases encounter")
	t.eq(server.raid_wave, 0, "phase state resets")
	t.eq(server.raid_minions.size(), 0, "minion identities cleared")
	for id in old_minions:
		t.check(not server.zombies.has(id), "raid adds disappear on victory")
	var bag_count: int = server.bags.size()
	server._damage_target(fighter, {"kind": "zombie", "id": boss_id}, 2000.0)
	t.eq(server.bags.size(), bag_count, "dead boss never grants repeat loot")

	t.current = "server population cap and expiration"
	var next_id: int = server.new_id()
	var second := Zombie.new(next_id, "brute", at(215.0, 200.0), -1)
	RaidEncounter.empower(second)
	server.zombies[next_id] = second
	server.raid_boss_id = next_id
	server.raid_started_at = server.time - RaidEncounter.MAX_ENCOUNTER_SECONDS - 1.0
	server._tick_raid_encounter()
	t.eq(server.raid_boss_id, -1, "expired boss disappears")
	t.check(not server.zombies.has(next_id), "expired boss removed from world")
	t.eq(server.raid_minions.size(), 0, "no lingering adds after timeout")
