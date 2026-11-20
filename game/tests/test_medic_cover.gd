extends RefCounted
## True healer aggro rescue via a real equipped staff and party guardian.
## Tests actual Zombie.force_taunt/Threat integration, bounded targets,
## replays, cooldown, wrong gear, privacy and invalid positions.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const MedicCover = preload("res://scripts/shared/medic_cover.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _enemy(sim, world, x: float, medic_id: int):
	var zombie := Zombie.new(sim.new_id(), "brute", _at(world, x, 0.0))
	zombie.state = Zombie.State.CHASE
	zombie.target_id = medic_id
	sim.zombies[zombie.id] = zombie
	return zombie


func run(t) -> void:
	t.current = "medic cover requires real party, healer weapon and defender"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var medic = sim.add_player(81, "Medic")
	var tank = sim.add_player(82, "Guardian")
	var outsider = sim.add_player(83, "Outsider")
	medic.position = _at(world, 310.0, 0.0)
	tank.position = _at(world, 311.0, 0.0)
	outsider.position = _at(world, 311.0, 1.0)
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "not_in_party",
		"solo medic cannot redirect infection onto an unrelated survivor")
	t.check(sim.cmd_party_invite(81, 82).get("ok", false), "medic invites guardian")
	t.check(sim.cmd_party_accept(82).get("ok", false), "guardian joins real group")
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "need_restoration_staff",
		"ordinary unarmed survivor is not a restoration medic")
	medic.inventory.add("restoration_staff_1", 1)
	t.check(medic.inventory.equip("restoration_staff_1"),
		"medic physically owns real equipped restoration staff")
	t.check(MedicCover.has_staff(medic), "staff type and possession are validated")
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "no_guardian",
		"restoration medic cannot force unarmed ally to take aggro")
	tank.inventory.add("club_1", 1)
	t.check(tank.inventory.equip("club_1"), "ally equips real melee guardian weapon")
	t.check(MedicCover.guardian_ok(medic, tank, sim.parties, world),
		"one nearby equipped real party defender is eligible")
	t.check(not MedicCover.guardian_ok(medic, outsider, sim.parties, world),
		"outside player cannot be drafted as a tank")
	t.check(not MedicCover.guardian_ok(medic, medic, sim.parties, world),
		"medic cannot redirect aggro to themselves")
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "no_engaged_infected",
		"no engaged enemies means no cooldown or free aggro manipulation")

	t.current = "no cooldown for refused energy, distance, or fake targets"
	var enemy = _enemy(sim, world, 312.0, medic.id)
	var idle = _enemy(sim, world, 313.0, medic.id)
	idle.state = Zombie.State.IDLE
	var foreign = _enemy(sim, world, 314.0, outsider.id)
	t.check(MedicCover.can_redirect(enemy, medic, tank, world),
		"current authentic infected pursuit of medic is eligible")
	t.check(not MedicCover.can_redirect(idle, medic, tank, world),
		"idle infected with stale player target must remain unaware")
	t.check(not MedicCover.can_redirect(foreign, medic, tank, world),
		"infected engaging a stranger never get dragged onto the guardian")
	medic.combat_energy = 0.0
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "no_energy",
		"no combat energy prevents an aggro rescue")
	t.near(medic.medic_cover_cooldown, 0.0, 0.001,
		"failed emergency cast never starts cooldown")
	medic.combat_energy = 100.0
	tank.position = _at(world, 340.0, 0.0)
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "no_guardian",
		"server does not authorize long-distance healers to request cover")
	tank.position = _at(world, 311.0, 0.0)
	tank.position = Vector3(311.0, medic.position.y + MedicCover.MAX_HEIGHT + 1.0, 0.0)
	t.check(not MedicCover.guardian_ok(medic, tank, sim.parties, world),
		"cross-floor rescue blocked")
	tank.position = _at(world, 311.0, 0.0)
	medic.position = Vector3(INF, 0.0, 0.0)
	t.check(not MedicCover.guardian_ok(medic, tank, sim.parties, world),
		"invalid coordinates cannot forge a call for cover")
	medic.position = _at(world, 310.0, 0.0)

	t.current = "real healing hate transfers only actual known infected to defender"
	t.check(Threat.record(enemy.threat, medic.id, 80.0),
		"authentic healer threat starts on the infected's server table")
	var before_energy: float = medic.combat_energy
	var rescued: Dictionary = sim.cmd_medic_cover(81)
	t.check(bool(rescued.get("ok", false)), "equipped medic gets a real guardian response")
	t.eq(int(rescued.get("guardian", -1)), tank.id, "the server selects actual guardian")
	t.eq(int(rescued.get("count", -1)), 1,
		"idle and unrelated enemies are not redirected")
	t.near(medic.combat_energy, before_energy - MedicCover.ENERGY_COST, 0.001,
		"successful rescue costs 24 combat energy exactly once")
	t.near(medic.medic_cover_cooldown, MedicCover.COOLDOWN, 0.001,
		"server applies full 30-second cooldown")
	t.eq(enemy.target_id, tank.id,
		"active infected immediately switches from medic to defender")
	t.eq(enemy.forced_target_id, tank.id,
		"server-owned forced target ID belongs to actual guardian")
	t.near(enemy.forced_target_seconds, MedicCover.TAUNT_SECONDS, 0.001,
		"redirected enemy is forced to focus the guardian for two seconds")
	t.near(float(enemy.threat.get(medic.id, -1.0)), 28.0, 0.001,
		"only real previously earned healer threat is reduced to 35 percent")
	t.check(float(enemy.threat.get(tank.id, 0.0)) > 0.0,
		"existing zombie force_taunt records the defender's bounded threat")
	t.eq(idle.target_id, medic.id, "idle enemies are never provoked by the call")
	t.eq(foreign.target_id, outsider.id, "other parties keep their original enemies")
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "cooldown",
		"rapid replay cannot redirect a second pack")
	t.near(medic.combat_energy, 100.0 - MedicCover.ENERGY_COST, 0.001,
		"rejected replay never charges energy a second time")
	t.near(float(sim.snapshot_for(81)["you"]["medic_cover_cooldown"]),
		MedicCover.COOLDOWN, 0.001, "client HUD reads only private server cooldown")
	t.near(float(sim.snapshot_for(83)["you"]["medic_cover_cooldown"]),
		0.0, 0.001, "outsiders do not observe another player's cooldown")

	t.current = "private ally and healer notifications only"
	var report: Array = sim.events.filter(func(e): return e.get("type", "") == "medic_cover")
	t.eq(report.size(), 1, "one validated rescue emits a single summary")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_medic_cover"), "authenticated reliable RPC exists")
	if report.size() == 1:
		t.check(net._event_visible_to(report[0], medic.id), "medic sees own request")
		t.check(net._event_visible_to(report[0], tank.id), "actual guardian hears call")
		t.check(not net._event_visible_to(report[0], outsider.id),
			"unrelated players cannot read emergency aggro-transfer events")
		t.check(not report[0].has("targets") and not report[0].has("threat"),
			"network event does not transmit mob IDs or private hate tables")
	net.free()

	t.current = "real AI keeps the short guardian challenge"
	var observations: Dictionary = {}
	observations[medic.id] = {"position": medic.position, "alive": true, "safe": false}
	observations[tank.id] = {"position": tank.position, "alive": true, "safe": false}
	enemy._select_target(observations, Vector2(enemy.position.x, enemy.position.z))
	t.eq(enemy.target_id, tank.id,
		"actual zombie brain maintains server-authorized guardian focus")

	t.current = "bosses, already taunted enemies and unrelated aggro remain untouched"
	var boss = _enemy(sim, world, 312.5, medic.id)
	RaidEncounter.empower(boss)
	boss.state = Zombie.State.CHASE
	t.check(not MedicCover.can_redirect(boss, medic, tank, world),
		"medic rescue cannot steal raid boss targets")
	var already = _enemy(sim, world, 312.7, medic.id)
	already.forced_target_id = outsider.id
	already.forced_target_seconds = 1.5
	t.check(not MedicCover.can_redirect(already, medic, tank, world),
		"another guardian's forced taunt cannot be overwritten")

	t.current = "max 3 real infected and stable selection"
	medic.medic_cover_cooldown = 0.0
	var mob_a = _enemy(sim, world, 313.0, medic.id)
	var mob_b = _enemy(sim, world, 314.0, medic.id)
	var mob_c = _enemy(sim, world, 315.0, medic.id)
	var mob_d = _enemy(sim, world, 316.0, medic.id)
	var multi: Dictionary = sim.cmd_medic_cover(medic.id)
	t.check(multi.get("ok", false), "second real fight can be rescued after cooldown")
	t.eq(int(multi.get("count", -1)), MedicCover.MAX_ENEMIES,
		"no more than three engaged infected can be redirected per cast")
	t.eq(mob_a.target_id, tank.id, "lowest-ID eligible infected selected")
	t.eq(mob_b.target_id, tank.id, "next eligible infected selected")
	t.eq(mob_c.target_id, tank.id, "third eligible infected selected")
	t.eq(mob_d.target_id, medic.id, "fourth infected stays engaged with the medic")

	t.current = "death, equipment loss and cooldown time prevent extra transfers"
	medic.medic_cover_cooldown = 0.0
	medic.inventory.remove("restoration_staff_1", 1)
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "need_restoration_staff",
		"ghost equipment cannot authorize the healer ability")
	medic.inventory.add("restoration_staff_1", 1)
	medic.inventory.equip("restoration_staff_1")
	tank.inventory.remove("club_1", 1)
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "no_guardian",
		"guardian losing the held melee weapon is immediately disqualified")
	tank.inventory.add("club_1", 1)
	tank.inventory.equip("club_1")
	medic.survival.hurt(999.0)
	t.eq(sim.cmd_medic_cover(81).get("reason", ""), "dead",
		"dead medic can never issue an emergency call")
	sim._on_player_death(medic, -enemy.id)
	sim._spawn_player(medic)
	t.near(medic.medic_cover_cooldown, 0.0, 0.001,
		"manually completed session cooldown remains zero after respawn")
