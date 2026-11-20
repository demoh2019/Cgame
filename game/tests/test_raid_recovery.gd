extends RefCounted
## Raid counterattack: only a real server-resolved boss slam opens an
## ephemeral vulnerability window. Ordinary infected and PvP stay unchanged.

const RaidRecovery = preload("res://scripts/shared/raid_recovery.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "post-slam rules apply only to a living raid boss"
	var normal = Zombie.new(61, "brute", Vector3.ZERO)
	var boss = Zombie.new(62, "brute", Vector3.ZERO)
	RaidEncounter.empower(boss)
	t.near(RaidRecovery.window_seconds(normal), 0.0, 0.001,
		"ordinary infected do not acquire raid exposure")
	t.near(RaidRecovery.window_seconds(boss), 4.0, 0.001,
		"phase one opens a four-second counterattack window")
	t.near(RaidRecovery.remaining(boss, 104.0, 100.0), 4.0, 0.001,
		"client can show the remaining authoritative time")
	t.near(RaidRecovery.amplify(10.0, boss, 104.0, 100.0), 11.5, 0.001,
		"boss armor break provides exactly fifteen percent extra PvE damage")
	t.near(RaidRecovery.amplify(10.0, normal, 104.0, 100.0), 10.0, 0.001,
		"ordinary zombies cannot inherit the bonus")
	t.near(RaidRecovery.amplify(10.0, boss, 104.0, 104.0), 10.0, 0.001,
		"expiry boundary ends the bonus exactly")
	t.near(RaidRecovery.remaining(boss, 104.0, 105.0), 0.0, 0.001,
		"expired timers are never shown")
	t.near(RaidRecovery.amplify(10.0, boss, NAN, 100.0), 10.0, 0.001,
		"invalid server clock cannot create a damage multiplier")
	t.near(RaidRecovery.amplify(NAN, boss, 104.0, 100.0), 0.0, 0.001,
		"invalid attack damage is rejected")
	t.near(RaidRecovery.amplify(-3.0, boss, 104.0, 100.0), 0.0, 0.001,
		"negative damage is never amplified")
	boss.health = RaidEncounter.BOSS_HEALTH * RaidEncounter.ENRAGE_HEALTH_FRACTION
	t.check(RaidEncounter.try_enrage(boss), "server transitions this boss to phase two")
	t.near(RaidRecovery.window_seconds(boss), 2.5, 0.001,
		"enraged boss gives a shorter punish opportunity")
	boss.take_damage(10000.0)
	t.near(RaidRecovery.window_seconds(boss), 0.0, 0.001,
		"dead boss has no vulnerability window")
	t.near(RaidRecovery.amplify(10.0, boss, 104.0, 100.0), 10.0, 0.001,
		"dead bosses cannot receive boosted damage")

	t.current = "real telegraphed strike creates server-owned exposure"
	var world := WorldGen.new(67)
	var sim := GameServer.new(world, 67)
	var fighter = sim.add_player(200, "Fighter")
	var spectator = sim.add_player(201, "Distant")
	fighter.position = _at(world, 851.0, 0.0)
	spectator.position = _at(world, 2500.0, 0.0)
	var raid = Zombie.new(sim.new_id(), "brute", _at(world, 853.0, 0.0), -1)
	RaidEncounter.empower(raid)
	sim.zombies[raid.id] = raid
	sim.raid_boss_id = raid.id
	sim.time = 100.0
	sim.raid_started_at = sim.time
	sim.raid_next_slam_at = sim.time
	raid.target_id = fighter.id
	sim._tick_raid_encounter()
	t.check(not sim.raid_pending_slam.is_empty(),
		"server schedules a warning, never instant armor vulnerability")
	t.near(sim.raid_exposed_until, 0.0, 0.001,
		"pre-slam warning does not expose armor")
	t.near(RaidRecovery.remaining(raid, sim.raid_exposed_until, sim.time),
		0.0, 0.001, "no free counterattack during the telegraph")
	sim.time += RaidEncounter.SLAM_WARNING + 0.01
	sim._tick_raid_encounter()
	t.check(sim.raid_pending_slam.is_empty(),
		"telegraphed slam resolves exactly once")
	t.near(sim.raid_exposed_until - sim.time, RaidRecovery.NORMAL_SECONDS, 0.001,
		"resolved slam creates a real four-second vulnerability")
	var slam_events: Array = []
	for event in sim.events:
		if str(event.get("type", "")) == "raid_slam":
			slam_events.append(event)
	t.eq(slam_events.size(), 1, "a single completed slam generates one raid event")
	if slam_events.size() == 1:
		t.near(float(slam_events[0].get("exposed_seconds", 0.0)),
			RaidRecovery.NORMAL_SECONDS, 0.001,
			"raid warning feedback announces the actual server window")
		var net := Net.new()
		net.role = "server"
		net.sim = sim
		t.check(net._event_visible_to(slam_events[0], 200),
			"local survivor receives the counterattack cue")
		t.check(not net._event_visible_to(slam_events[0], 201),
			"faraway stranger cannot receive distant raid intelligence")
		net.free()

	var state: Dictionary = sim.snapshot_for(200)
	var found: bool = false
	for enemy in state.get("zombies", []):
		if int(enemy.get("id", -1)) == raid.id:
			found = true
			t.near(float(enemy.get("raid_exposed_seconds", 0.0)),
				RaidRecovery.NORMAL_SECONDS, 0.001,
				"nearby snapshots show true remaining vulnerability")
	t.check(found, "raid boss is visible alongside its normal enemy stats")
	var distant_has_boss: bool = false
	for enemy in sim.snapshot_for(201).get("zombies", []):
		if int(enemy.get("id", -1)) == raid.id:
			distant_has_boss = true
	t.check(not distant_has_boss,
		"far-off clients receive no boss or exposed timer beyond interest radius")

	t.current = "damage increase comes from the existing authoritative combat path"
	var starting_health: float = raid.health
	sim._damage_target(fighter, {"kind": "zombie", "id": raid.id}, 10.0)
	t.near(starting_health - raid.health, 11.5, 0.001,
		"actual confirmed hit deals exactly fifteen percent more boss damage")
	var ordinary = Zombie.new(sim.new_id(), "walker", _at(world, 855.0, 0.0))
	sim.zombies[ordinary.id] = ordinary
	starting_health = ordinary.health
	sim._damage_target(fighter, {"kind": "zombie", "id": ordinary.id}, 10.0)
	t.near(starting_health - ordinary.health, 10.0, 0.001,
		"another infected remains unaffected during boss exposure")
	sim.time = sim.raid_exposed_until + 0.01
	starting_health = raid.health
	sim._damage_target(fighter, {"kind": "zombie", "id": raid.id}, 10.0)
	t.near(starting_health - raid.health, 10.0, 0.001,
		"attack after deadline deals normal damage")
	for enemy in sim.snapshot_for(200).get("zombies", []):
		if int(enemy.get("id", -1)) == raid.id:
			t.near(float(enemy.get("raid_exposed_seconds", -1.0)), 0.0, 0.001,
				"snapshot timer expires independently of visual effects")

	t.current = "phase two recovery is shorter and death clears all residue"
	sim.time += 1.0
	raid.health = RaidEncounter.BOSS_HEALTH * RaidEncounter.ENRAGE_HEALTH_FRACTION
	t.check(RaidEncounter.try_enrage(raid), "real boss can enrage at low HP")
	sim.raid_pending_slam = {"id": raid.id, "x": raid.position.x,
		"z": raid.position.z, "at": sim.time}
	sim._tick_raid_encounter()
	t.near(sim.raid_exposed_until - sim.time, RaidRecovery.ENRAGED_SECONDS,
		0.001, "enraged slam opens only a two-and-half-second recovery")
	starting_health = raid.health
	sim._damage_target(fighter, {"kind": "zombie", "id": raid.id}, 10.0)
	t.near(starting_health - raid.health, 11.5, 0.001,
		"phase two still permits a bounded counterattack")
	sim._damage_target(fighter, {"kind": "zombie", "id": raid.id}, 1000.0)
	t.eq(sim.raid_boss_id, -1, "boss death ends the active encounter")
	t.near(sim.raid_exposed_until, 0.0, 0.001,
		"kill clears server's temporary exposed state")
