extends RefCounted
## Telegraphed directional raid attacks use fixed server geometry, never
## client-selected damage, targets, aim or cooldowns.

const RaidCone = preload("res://scripts/shared/raid_cone.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _at(x: float, z: float) -> Vector3:
	return Vector3(x, 5.0, z)


func run(t) -> void:
	t.current = "finite locked cone geometry is resistant to forged directions"
	var origin: Vector3 = _at(0.0, 0.0)
	var forward := Vector2(1.0, 0.0)
	t.check(RaidCone.can_aim(origin, _at(13.0, 0.0)), "boss can aim within range")
	t.check(not RaidCone.can_aim(origin, _at(30.0, 0.0)), "cannot aim beyond reach")
	t.check(not RaidCone.can_aim(origin, origin), "zero-length direction rejected")
	t.check(not RaidCone.can_aim(origin, Vector3(INF, 5.0, 0.0)),
		"nonfinite aim position rejected")
	t.near(RaidCone.direction(origin, _at(3.0, 0.0)).x, 1.0, 0.001,
		"direction is normalized from authentic positions")
	t.eq(RaidCone.direction(origin, origin), Vector2.ZERO,
		"invalid target does not produce an arbitrary angle")
	t.check(RaidCone.in_sector(origin, forward, _at(12.9, 0.0)),
		"target in front is hit")
	t.check(not RaidCone.in_sector(origin, forward, _at(13.1, 0.0)),
		"target beyond the reach is safe")
	t.check(not RaidCone.in_sector(origin, forward, _at(-2.0, 0.0)),
		"behind the boss is a safe counterplay position")
	t.check(not RaidCone.in_sector(origin, forward, _at(0.0, 3.0)),
		"sidestepping out of the frontal sector avoids the strike")
	t.check(not RaidCone.in_sector(origin, forward, Vector3(2.0, 8.6, 0.0)),
		"targets on another floor cannot be hit")
	t.check(not RaidCone.in_sector(origin, Vector2(50.0, 0.0), _at(1.0, 0.0)),
		"un-normalized direction cannot expand the sector")
	t.check(not RaidCone.in_sector(origin, Vector2(NAN, 0.0), _at(1.0, 0.0)),
		"nonfinite direction cannot hit")
	t.check(not RaidCone.in_sector(origin, forward, Vector3(INF, 0.0, 0.0)),
		"nonfinite target cannot be struck")

	t.current = "real server locks aim, announces windup and limits visibility"
	var world := WorldGen.new(79)
	var server := GameServer.new(world, 79)
	var front = server.add_player(301, "Front")
	var side = server.add_player(302, "Side")
	var rear = server.add_player(303, "Behind")
	var dodger = server.add_player(304, "Dodger")
	var far = server.add_player(305, "Unrelated")
	front.position = _at(855.0, 0.0)
	side.position = _at(854.0, 10.0)
	rear.position = _at(845.0, 0.0)
	dodger.position = _at(855.0, 1.0)
	far.position = _at(2500.0, 0.0)
	var boss = Zombie.new(server.new_id(), "brute", _at(850.0, 0.0), -1)
	RaidEncounter.empower(boss)
	server.zombies[boss.id] = boss
	server.raid_boss_id = boss.id
	server.time = 100.0
	server.raid_started_at = server.time
	server.raid_next_slam_at = server.time + 100.0
	server.raid_next_cone_at = server.time
	boss.target_id = front.id
	server._tick_raid_encounter()
	t.check(not server.raid_pending_cone.is_empty(),
		"real nearby living target triggers a server-authored cone warning")
	t.eq(int(server.raid_pending_cone.get("id", -1)), boss.id,
		"windup is bound to actual active raid boss")
	t.near(float(server.raid_pending_cone.get("dx", 0.0)), 1.0, 0.001,
		"server locked the initial frontal direction")
	t.near(float(server.raid_pending_cone["at"]) - server.time,
		RaidCone.WINDUP_SECONDS, 0.001, "a 2.2s warning precedes damage")
	var near_snapshot: Dictionary = server.snapshot_for(301)
	t.check(near_snapshot.has("raid_cone_telegraph"),
		"nearby player sees exact server cone")
	t.eq(int(near_snapshot["raid_cone_telegraph"]["id"]), boss.id,
		"snapshot warning is not a client-generated guess")
	t.check(not server.snapshot_for(305).has("raid_cone_telegraph"),
		"faraway player does not see private raid coordinates")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	var warnings: Array = server.events.filter(
		func(event): return event.get("type", "") == "raid_cone_warning")
	t.eq(warnings.size(), 1, "exactly one warning is broadcast per attack")
	if warnings.size() == 1:
		t.check(net._event_visible_to(warnings[0], 301),
			"nearby survivors receive a telegraph event")
		t.check(not net._event_visible_to(warnings[0], 305),
			"server does not broadcast raid information globally")
	net.free()
	var radar := Radar.new()
	t.check(radar.has_method("_draw_raid_cone"), "the radar can draw the actual marked sector")
	radar.free()

	var front_before: float = front.survival.health
	var side_before: float = side.survival.health
	var rear_before: float = rear.survival.health
	var dodge_before: float = dodger.survival.health
	dodger.dodge_immunity = 3.0
	server.time += 0.5
	server._tick_raid_encounter()
	t.near(front.survival.health, front_before, 0.001,
		"windup does not inflict instantaneous damage")
	t.eq(server.events.filter(
		func(event): return event.get("type", "") == "raid_cone_struck").size(), 0,
		"no hit event before windup ends")
	# The locked direction stays the same even if the boss changes targets.
	boss.target_id = side.id
	server.time = 100.0 + RaidCone.WINDUP_SECONDS + 0.01
	server._tick_raid_encounter()
	t.check(server.raid_pending_cone.is_empty(), "resolved attack clears the active telegraph")
	t.near(front_before - front.survival.health, RaidCone.FIRST_DAMAGE, 0.001,
		"front player suffers real authoritative cone damage")
	t.near(side.survival.health, side_before, 0.001,
		"changing the boss target does not rotate the warned cone")
	t.near(rear.survival.health, rear_before, 0.001,
		"survivor behind the boss avoids the attack")
	t.near(dodger.survival.health, dodge_before, 0.001,
		"existing dodge immunity also avoids a frontal cleave")
	t.eq(server.events.filter(
		func(event): return event.get("type", "") == "raid_cone_struck").size(), 1,
		"one attack generates one terminal network event")
	t.near(server.raid_exposed_until, 0.0, 0.001,
		"cone does not fake the post-slam boss vulnerability")
	server._tick_raid_encounter()
	t.eq(server.events.filter(
		func(event): return event.get("type", "") == "raid_cone_struck").size(), 1,
		"duplicate ticks cannot hit the same telegraph again")
	t.check(not server.snapshot_for(301).has("raid_cone_telegraph"),
		"clients clear old attack warning from subsequent snapshots")

	t.current = "independent cooldowns, enrage and boss cleanup"
	server.time = 100.0 + RaidCone.FIRST_COOLDOWN - 0.01
	boss.target_id = front.id
	server._tick_raid_encounter()
	t.check(server.raid_pending_cone.is_empty(), "first-phase cooldown blocks premature recasts")
	server.time = 100.0 + RaidCone.FIRST_COOLDOWN
	server._tick_raid_encounter()
	t.check(not server.raid_pending_cone.is_empty(), "another sector starts after cooldown")
	# Existing slam always has priority over a new cone, but a running
	# telegraph must be allowed to resolve before scheduling a slam.
	server.time += RaidCone.WINDUP_SECONDS + 0.01
	server._tick_raid_encounter()
	server.raid_wave = 2 # Avoid adding unrelated minions in the unit test.
	boss.health = RaidEncounter.BOSS_HEALTH * 0.34
	t.check(RaidEncounter.try_enrage(boss), "warlord transitions to enraged damage")
	t.near(RaidCone.cooldown(boss), RaidCone.ENRAGED_COOLDOWN, 0.001,
		"phase two has tighter cooldown")
	t.near(RaidCone.damage(boss), RaidCone.ENRAGED_DAMAGE, 0.001,
		"phase two deals more directional PvE damage")
	server.raid_next_cone_at = server.time
	server._tick_raid_encounter()
	t.check(not server.raid_pending_cone.is_empty(), "enraged boss can wind up another cleave")
	server.raid_pending_slam = {"id": boss.id, "x": 850.0, "z": 0.0,
		"at": server.time + 1.0}
	server.time += 0.1
	server._tick_raid_encounter()
	t.check(not server.raid_pending_cone.is_empty(),
		"overlapping slam telegraph defers resolving a pending cone")
	# Encounter retreat removes every attack without delivering damage.
	server.raid_started_at = server.time - RaidEncounter.MAX_ENCOUNTER_SECONDS - 1.0
	server._tick_raid_encounter()
	t.eq(server.raid_boss_id, -1, "raid retreat ends the active encounter")
	t.check(server.raid_pending_slam.is_empty() and server.raid_pending_cone.is_empty(),
		"retreat clears both types of attack warning")
	t.near(server.raid_exposed_until, 0.0, 0.001,
		"retreat also clears prior vulnerability")
