extends RefCounted
## A real server-owned second phase; phase transitions, damage, replication
## and network visibility must be bounded and resistant to replay.

const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "raid phase cannot affect normal infected"
	var plain = Zombie.new(16, "brute", Vector3(850, 0, 0))
	plain.health = RaidEncounter.BOSS_HEALTH * 0.1
	t.check(not RaidEncounter.try_enrage(plain), "ordinary brutes cannot enrage")
	t.check(not plain.raid_enraged, "normal enemy is unchanged")
	var first = Zombie.new(17, "brute", Vector3(850, 0, 0))
	RaidEncounter.empower(first)
	t.near(RaidEncounter.slam_damage(first), RaidEncounter.SLAM_DAMAGE, 0.001,
		"phase one has normal slam damage")
	first.health = RaidEncounter.BOSS_HEALTH * RaidEncounter.ENRAGE_HEALTH_FRACTION + 1.0
	t.check(not RaidEncounter.try_enrage(first), "phase one continues above threshold")
	first.health = RaidEncounter.BOSS_HEALTH * RaidEncounter.ENRAGE_HEALTH_FRACTION
	t.check(RaidEncounter.try_enrage(first), "threshold triggers phase two")
	t.check(first.raid_enraged, "phase state is permanently set for this boss")
	t.near(float(first.data["damage"]),
		RaidEncounter.BOSS_DAMAGE * RaidEncounter.ENRAGE_MELEE_MULTIPLIER, 0.001,
		"melee damage scales only on this boss")
	t.near(RaidEncounter.slam_damage(first), RaidEncounter.ENRAGE_SLAM_DAMAGE, 0.001,
		"enrage increases area damage")
	t.near(RaidEncounter.slam_cooldown(first), RaidEncounter.ENRAGE_SLAM_COOLDOWN, 0.001,
		"phase two launches slams more frequently")
	t.check(not RaidEncounter.try_enrage(first), "replaying enrage cannot stack damage")
	t.near(float(first.data["damage"]),
		RaidEncounter.BOSS_DAMAGE * RaidEncounter.ENRAGE_MELEE_MULTIPLIER, 0.001,
		"repeat tick cannot double damage")
	t.near(float(plain.data["damage"]), 26.0, 0.001,
		"shared brute stats remain unchanged")
	var dead = Zombie.new(18, "brute", Vector3.ZERO)
	RaidEncounter.empower(dead)
	dead.take_damage(2000.0)
	t.check(not RaidEncounter.try_enrage(dead), "dead bosses cannot enter phase two")

	t.current = "authoritative server phase transition and private event"
	var world := WorldGen.new(67)
	var server := GameServer.new(world, 67)
	var survivor = server.add_player(200, "Fighter")
	survivor.position = _at(world, 851.0, 0.0)
	var distant = server.add_player(201, "Distant")
	distant.position = _at(world, 2500.0, 0.0)
	var boss = Zombie.new(server.new_id(), "brute", _at(world, 853.0, 0.0), -1)
	RaidEncounter.empower(boss)
	server.zombies[boss.id] = boss
	server.raid_boss_id = boss.id
	server.time = 100.0
	server.raid_started_at = server.time
	server.raid_next_slam_at = server.time + 14.0
	boss.health = RaidEncounter.BOSS_HEALTH * RaidEncounter.ENRAGE_HEALTH_FRACTION + 1.0
	server._tick_raid_encounter()
	t.check(not boss.raid_enraged, "no early phase transition")
	boss.health = RaidEncounter.BOSS_HEALTH * RaidEncounter.ENRAGE_HEALTH_FRACTION
	server._tick_raid_encounter()
	t.check(boss.raid_enraged, "server advances boss at threshold")
	t.near(server.raid_next_slam_at, 108.0, 0.001,
		"phase change brings next slam forward without immediate hit")
	var phase_events: Array = server.events.filter(
		func(event): return str(event.get("type", "")) == "raid_enraged")
	t.eq(phase_events.size(), 1, "one phase announcement, never per-tick spam")
	server._tick_raid_encounter()
	t.eq(server.events.filter(
		func(event): return str(event.get("type", "")) == "raid_enraged").size(), 1,
		"further updates cannot duplicate announcement")
	var snapshot: Dictionary = server.snapshot_for(200)
	var seen := false
	for entity in snapshot["zombies"]:
		if int(entity["id"]) == boss.id:
			seen = true
			t.check(bool(entity.get("raid_enraged", false)),
				"nearby client learns the real phase from server snapshot")
	t.check(seen, "enraged boss remains a visible existing enemy")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to(phase_events[0], 200), "nearby fighter receives phase warning")
	t.check(not net._event_visible_to(phase_events[0], 201),
		"distant nonparticipants cannot track boss location")
	net.free()

	t.current = "enraged telegraph retains dodge and area bounds"
	boss.target_id = 200
	server.time = server.raid_next_slam_at
	server._tick_raid_encounter()
	t.check(not server.raid_pending_slam.is_empty(),
		"phase two creates a visible warning instead of instant damage")
	t.near(server.raid_next_slam_at, server.time + RaidEncounter.ENRAGE_SLAM_COOLDOWN,
		0.001, "future strikes follow phase-two cooldown")
	var center := Vector2(float(server.raid_pending_slam["x"]),
		float(server.raid_pending_slam["z"]))
	survivor.position = _at(world, center.x, center.y)
	distant.position = _at(world, center.x + RaidEncounter.SLAM_RADIUS + 2.0, center.y)
	var before: float = survivor.survival.health
	var distant_before: float = distant.survival.health
	server.time += RaidEncounter.SLAM_WARNING + 0.01
	server._tick_raid_encounter()
	t.near(survivor.survival.health, before - RaidEncounter.ENRAGE_SLAM_DAMAGE, 0.001,
		"enraged AoE damage is calculated by the server")
	t.near(distant.survival.health, distant_before, 0.001,
		"out-of-radius target is safe")
	var hp_after: float = survivor.survival.health
	server._tick_raid_encounter()
	t.near(survivor.survival.health, hp_after, 0.001,
		"the same attack is never resolved twice")
