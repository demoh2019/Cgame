extends RefCounted
## Server-authoritative two-player interrupt: no solo burst, free credit,
## stolen party contribution, expired warning, double event or PvP effect.
const RaidInterrupt = preload("res://scripts/shared/raid_interrupt.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const RaidRecovery = preload("res://scripts/shared/raid_recovery.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "coordinated raid interrupt cannot be forged or soloed"
	var ordinary = Zombie.new(11, "brute", Vector3.ZERO)
	var boss = Zombie.new(12, "brute", Vector3.ZERO)
	RaidEncounter.empower(boss)
	var warning := {"id": boss.id, "at": 102.0}
	t.check(not RaidInterrupt.record_hit(warning, ordinary, 1, 5, 1000.0, 100.0),
		"ordinary infected never have interruptable casts")
	t.check(not RaidInterrupt.record_hit(warning, boss, 1, 0, 1000.0, 100.0),
		"solo players cannot create party credit")
	t.check(not RaidInterrupt.record_hit(warning, boss, 1, 5, NAN, 100.0),
		"invalid damage cannot count")
	t.check(not RaidInterrupt.record_hit(warning, boss, 1, 5, 100.0, 102.0),
		"attacks after telegraph deadline are rejected")
	t.check(not RaidInterrupt.record_hit(warning, boss, 1, 5, 1000.0, 100.0),
		"one massive hit is clamped to a single-player contribution")
	t.near(float(warning["contributors"][1]), RaidInterrupt.CREDIT_PER_PLAYER, 0.001,
		"player contribution has a strict per-warning limit")
	t.check(not RaidInterrupt.record_hit(warning, boss, 2, 6, 1000.0, 100.0),
		"a rival party cannot finish another party's interrupt")
	t.check(not RaidInterrupt.record_hit(warning, boss, 1, 5, 1000.0, 100.0),
		"repeating hits from the same player adds no extra credit")
	t.check(RaidInterrupt.record_hit(warning, boss, 2, 5, 10.0, 100.0),
		"two party members with enough damage can break the cast")
	t.eq(warning["contributors"].size(), 2,
		"real distinct contributors are counted exactly once")
	boss.take_damage(10000.0)
	t.check(not RaidInterrupt.record_hit({"id": boss.id, "at": 102.0},
		boss, 3, 5, 30.0, 100.0), "dead boss casts are not interruptable")

	t.current = "real server attacks break only an active warning"
	var world := WorldGen.new(67)
	var server := GameServer.new(world, 67)
	var first = server.add_player(701, "Vanguard")
	var second = server.add_player(702, "Striker")
	var stranger = server.add_player(703, "Outsider")
	first.position = _at(world, 851.0, 0.0)
	second.position = _at(world, 851.0, 1.0)
	stranger.position = _at(world, 851.0, 2.0)
	t.check(server.cmd_party_invite(first.id, second.id).get("ok", false),
		"party leader invites a real nearby survivor")
	t.check(server.cmd_party_accept(second.id).get("ok", false),
		"second fighter joins the authoritative party")
	var raid = Zombie.new(server.new_id(), "brute", _at(world, 853.0, 0.0), -1)
	RaidEncounter.empower(raid)
	raid.target_id = first.id
	server.zombies[raid.id] = raid
	server.raid_boss_id = raid.id
	server.time = 100.0
	server.raid_started_at = server.time
	server.raid_next_slam_at = server.time
	server._tick_raid_encounter()
	t.check(not server.raid_pending_slam.is_empty(),
		"normal raid AI starts a telegraphed slam")
	t.near(server.raid_exposed_until, 0.0, 0.001,
		"telegraph itself does not grant vulnerability")
	server._damage_target(first, {"kind": "zombie", "id": raid.id}, 20.0)
	t.eq(server.raid_pending_slam.get("contributors", {}).size(), 0,
		"no equipped weapon means no interrupt credit")
	first.inventory.add("club_1", 1)
	second.inventory.add("club_1", 1)
	first.inventory.equip("club_1")
	second.inventory.equip("club_1")
	server._damage_target(stranger, {"kind": "zombie", "id": raid.id}, 50.0)
	t.eq(server.raid_pending_slam.get("contributors", {}).size(), 0,
		"ungrouped attacker cannot contribute despite damaging boss")
	server._damage_target(first, {"kind": "zombie", "id": raid.id}, 20.0)
	t.eq(server.raid_pending_slam.get("contributors", {}).size(), 1,
		"real fighter counts once during the warning")
	server._damage_target(first, {"kind": "zombie", "id": raid.id}, 20.0)
	t.check(not server.raid_pending_slam.is_empty(),
		"repeated solo hits cannot complete a coordinated interrupt")
	server._damage_target(second, {"kind": "zombie", "id": raid.id}, 10.0)
	t.eq(server.raid_pending_slam, {}, "second member stops the scheduled slam")
	t.near(server.raid_exposed_until - server.time,
		RaidRecovery.NORMAL_SECONDS, 0.001,
		"successful teamwork opens the real post-slam damage window")
	var interrupts: Array = server.events.filter(
		func(event): return str(event.get("type", "")) == "raid_interrupted")
	t.eq(interrupts.size(), 1, "one authoritative interrupt event is emitted")
	if not interrupts.is_empty():
		t.near(float(interrupts[0].get("exposed_seconds", 0.0)),
			RaidRecovery.NORMAL_SECONDS, 0.001,
			"event includes only the real exposure duration")
		var net := Net.new()
		net.role = "server"
		net.sim = server
		t.check(net._event_visible_to(interrupts[0], first.id),
			"nearby participant receives the success notification")
		var far = server.add_player(704, "Far Witness")
		far.position = _at(world, 2500.0, 0.0)
		t.check(not net._event_visible_to(interrupts[0], far.id),
			"remote players cannot track raid progress")
		net.free()
	server._tick_raid_encounter()
	t.eq(server.events.filter(
		func(event): return str(event.get("type", "")) == "raid_interrupted").size(),
		1, "later raid ticks cannot replay an interrupted attack")
	t.eq(server.events.filter(
		func(event): return str(event.get("type", "")) == "raid_slam").size(),
		0, "interrupted strike never deals its scheduled area damage")
	var expired := {"id": raid.id, "at": server.time - 1.0}
	t.check(not RaidInterrupt.record_hit(expired, raid, first.id,
		server.parties.group_of(first.id), 30.0, server.time),
		"expired cast rejects even valid party damage")
