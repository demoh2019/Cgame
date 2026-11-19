extends RefCounted
## Deterministic dangerous-zone raid regression, using the real GameServer
## and Zombie combat with a small flat terrain to avoid procedural randomness.

const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const Party = preload("res://scripts/shared/party.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


class RaidWorld:
	extends RefCounted
	var world_seed: int = 501

	func zone_at(x: float, _z: float) -> int:
		return 2 if x > 100.0 else 0

	func is_safe(x: float, _z: float) -> bool:
		return x <= 100.0

	func height_at(_x: float, _z: float) -> float:
		return 3.0

	func is_water(_x: float, _z: float) -> bool:
		return false

	func blockers_near(_x: float, _z: float, _range: float) -> Array:
		return []


func _at(x: float, z: float) -> Vector3:
	return Vector3(x, 3.0, z)


func run(t) -> void:
	t.current = "boss rules and bounded treasure"
	t.eq(RaidEncounter.treasure(0), {}, "no raid payouts in safe zones")
	t.eq(RaidEncounter.treasure(1), {}, "yellow-zone loot is not raid loot")
	t.eq(int(RaidEncounter.treasure(2)["silver"]), 75, "red-zone boss reward is bounded")
	t.eq(int(RaidEncounter.treasure(3)["silver"]), 100, "black-zone boss pays more")
	t.check(not RaidEncounter.in_slam(Vector2.ZERO, _at(10, 0)),
		"slam cannot hit an out-of-radius survivor")
	t.check(RaidEncounter.in_slam(Vector2.ZERO, _at(3, 0)),
		"slam range uses horizontal distance only")
	t.check(not RaidEncounter.in_slam(Vector2.INF, _at(0, 0)),
		"invalid circle center cannot damage survivors")

	t.current = "party authority and danger requirements"
	var world := RaidWorld.new()
	var server := GameServer.new(world, 53)
	var leader = server.add_player(301, "Raid Leader")
	var ally = server.add_player(302, "Raid Fighter")
	var spectator = server.add_player(303, "Unrelated")
	leader.position = _at(0, 0)
	ally.position = _at(2, 0)
	spectator.position = _at(500, 500)
	server.time = RaidEncounter.START_DELAY
	server.tick_count = 20
	t.eq(RaidEncounter.eligible_leader(world, server.players, server.parties), -1,
		"solo and safe-hub survivors cannot trigger a world boss")
	server._tick_raid_encounter()
	t.eq(server.raid_boss_id, -1, "no solo world boss")
	leader.position = _at(200, 200)
	ally.position = _at(202, 201)
	t.eq(RaidEncounter.eligible_leader(world, server.players, server.parties), -1,
		"two nearby strangers cannot activate party content")
	t.check(server.cmd_party_invite(301, 302)["ok"], "real leader invites a real nearby player")
	t.check(server.cmd_party_accept(302)["ok"], "member joins before the encounter")
	t.eq(RaidEncounter.eligible_leader(world, server.players, server.parties), 301,
		"two grouped survivors in a red zone qualify")
	var site: Vector2 = RaidEncounter.spawn_site(world, server.players, leader.position)
	t.check(site.is_finite(), "safe boss spawn site is found away from all players")
	t.check(site.distance_to(Vector2(leader.position.x, leader.position.z))
		>= RaidEncounter.MIN_SPAWN_TO_LEADER, "boss cannot appear on a player")

	t.current = "one server-only boss, scaled stats and private network event"
	server._tick_raid_encounter()
	var boss_id: int = server.raid_boss_id
	t.check(boss_id > 0, "authoritative scheduler creates a boss after group assembled")
	if boss_id < 0:
		return
	var boss = server.zombies[boss_id]
	t.check(boss.raid_boss, "boss marked separately from random ruin elites")
	t.eq(boss.type, "brute", "boss uses existing infected AI")
	t.eq(boss.health, RaidEncounter.BOSS_HEALTH, "server scales health to raid difficulty")
	t.eq(float(boss.data["damage"]), RaidEncounter.BOSS_DAMAGE,
		"raid boss attack uses server-owned combat statistics")
	# The snapshot view is exercised in the full WorldGen integration suite.
	# This flat test world intentionally implements only spawn/combat primitives.
	var normal_spawn_count: int = server.zombies.size()
	server.tick_count = 40
	server._tick_raid_encounter()
	t.eq(server.zombies.size(), normal_spawn_count, "no second concurrent boss spawned")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	var arrival := {"type": "raid_started", "x": boss.position.x, "z": boss.position.z}
	t.check(net._event_visible_to(arrival, 301),
		"nearby team receives boss arrival")
	t.check(not net._event_visible_to(arrival, 303),
		"distant outsiders cannot see private encounter details")
	net.free()

	t.current = "telegraphed AoE can be dodged or walked out of"
	server.time = server.raid_next_slam_at
	server._tick_raid_encounter()
	t.check(not server.raid_pending_slam.is_empty(), "server warns before boss slam")
	t.eq(ally.survival.health, 100.0, "warning itself causes no damage")
	var center := Vector2(float(server.raid_pending_slam["x"]),
		float(server.raid_pending_slam["z"]))
	ally.position = _at(center.x, center.y)
	leader.position = _at(center.x + 3.0, center.y)
	leader.dodge_immunity = 1.0
	server.time += RaidEncounter.SLAM_WARNING + 0.01
	server._tick_raid_encounter()
	t.check(server.raid_pending_slam.is_empty(), "slam resolves once when windup ends")
	t.check(ally.survival.health < 100.0, "standing in danger area takes damage")
	t.eq(leader.survival.health, 100.0, "active dodge immunity avoids the slam")
	var health_after: float = ally.survival.health
	server._tick_raid_encounter()
	t.eq(ally.survival.health, health_after, "resolved attack cannot hit twice")

	t.current = "one boss death, shared world loot and real contributor XP"
	leader.inventory.add("club_1", 1)
	ally.inventory.add("club_1", 1)
	leader.inventory.equip("club_1")
	ally.inventory.equip("club_1")
	server._damage_target(ally, {"kind": "zombie", "id": boss_id}, 10.0)
	server._damage_target(leader, {"kind": "zombie", "id": boss_id}, 1000.0)
	t.eq(server.raid_boss_id, -1, "raid slot frees only on confirmed boss death")
	t.check(not boss.is_alive(), "boss is actually defeated")
	t.eq(leader.kills, 1, "only killer receives one personal kill")
	t.eq(ally.kills, 0, "assist does not fabricate personal kills")
	t.eq(ally.progression.combat_xp["melee"], Party.assist_xp(
		RaidEncounter.BOSS_MASTERY_XP), "real participant receives bounded assist mastery")
	t.eq(server.bags.size(), 1, "raid creates a single shared world bag")
	var drops: Dictionary = server.bags.values()[0]["items"]
	t.check(int(drops.get("infected_core", 0)) >= 4,
		"rare boss core materials exist in the shared world loot")
	t.check(int(drops.get("silver", 0)) >= 75, "raid treasure has guaranteed silver")
	server._damage_target(leader, {"kind": "zombie", "id": boss_id}, 1000.0)
	t.eq(server.bags.size(), 1, "repeated hits cannot duplicate the raid bag")
	t.eq(ally.progression.combat_xp["melee"], Party.assist_xp(
		RaidEncounter.BOSS_MASTERY_XP), "dead boss cannot duplicate assist XP")
	server._tick_raid_encounter()
	t.eq(server.raid_boss_id, -1, "600-second cooldown blocks immediate respawn")

	t.current = "expiry and replay cooldown"
	leader.position = _at(200, 200)
	ally.position = _at(202, 201)
	server.time = RaidEncounter.START_DELAY + RaidEncounter.COOLDOWN + 1.0
	server.tick_count = 60
	server._tick_raid_encounter()
	t.check(server.raid_boss_id > 0, "eligible party may face next boss after cooldown")
	if server.raid_boss_id > 0:
		var expired_id: int = server.raid_boss_id
		server.time += RaidEncounter.MAX_ENCOUNTER_SECONDS + 1.0
		server._tick_raid_encounter()
		t.eq(server.raid_boss_id, -1, "unfought encounter despawns within its time limit")
		t.check(not server.zombies.has(expired_id), "timed-out boss removed from world")
		t.eq(server.bags.size(), 1, "timeout produces no additional reward")
