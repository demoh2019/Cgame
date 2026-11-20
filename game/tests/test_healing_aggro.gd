extends RefCounted
## A medic earns combat threat only for real allied HP restored to someone
## already engaged by that living infected, with the same PvE leash/safety.

const HealingAggro = preload("res://scripts/shared/healing_aggro.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const PartyTriage = preload("res://scripts/shared/party_triage.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "bounded, strictly positive and independently earned heal threat"
	t.eq(HealingAggro.threat_for(0.0), 0.0, "no healing yields no hate")
	t.eq(HealingAggro.threat_for(-3.0), 0.0, "negative healing cannot earn hate")
	t.eq(HealingAggro.threat_for(NAN), 0.0, "NaN cannot enter combat threat")
	t.eq(HealingAggro.threat_for(INF), 0.0, "infinite fake healing cannot enter combat threat")
	t.near(HealingAggro.threat_for(28.0), 21.0, 0.001,
		"28 actually restored HP earns a modest amount of aggro")
	t.eq(HealingAggro.threat_for(999.0), HealingAggro.MAX_PER_ACTION,
		"one cast cannot overflow an infected threat list")
	var dummy := Zombie.new(1, "walker", Vector3.ZERO, -1)
	t.check(not HealingAggro.can_credit(dummy, Vector3(2, 0, 0),
		Vector3(3, 0, 0), 8), "idle unrelated infected are not aggroed by aid")
	dummy.target_id = 8
	t.check(HealingAggro.can_credit(dummy, Vector3(2, 0, 0),
		Vector3(3, 0, 0), 8), "infected fighting a patient notices nearby medicine")
	t.check(not HealingAggro.can_credit(dummy, Vector3(200, 0, 0),
		Vector3(3, 0, 0), 8), "medic cannot gain cross-map hate")
	t.check(not HealingAggro.can_credit(dummy, Vector3(2, 0, 0),
		Vector3(200, 0, 0), 8), "patient must remain near infected")
	t.check(not HealingAggro.can_credit(dummy, Vector3(NAN, 0, 0),
		Vector3(3, 0, 0), 8), "invalid positions do not create combat hate")

	t.current = "real first-aid attracts only engaged infected"
	var world := WorldGen.new(1011)
	var server := GameServer.new(world, 1011)
	var medic = server.add_player(101, "Medic")
	var fighter = server.add_player(102, "Fighter")
	var outsider = server.add_player(103, "Outsider")
	medic.position = _at(world, 301.0, 301.0)
	fighter.position = _at(world, 302.0, 301.0)
	outsider.position = _at(world, 303.0, 301.0)
	t.check(server.cmd_party_invite(101, 102).get("ok", false),
		"medic invites a real nearby ally")
	t.check(server.cmd_party_accept(102).get("ok", false),
		"fighter joins the same party")
	medic.inventory.add("bandage", 3)
	fighter.survival.hurt(50.0)
	var infected := Zombie.new(server.new_id(), "walker", _at(world, 307.0, 301.0), -1)
	infected.target_id = fighter.id
	infected.threat[fighter.id] = 8.0
	server.zombies[infected.id] = infected
	var idle := Zombie.new(server.new_id(), "walker", _at(world, 306.0, 301.0), -1)
	server.zombies[idle.id] = idle
	var stranger_enemy := Zombie.new(server.new_id(), "walker", _at(world, 307.0, 302.0), -1)
	stranger_enemy.target_id = outsider.id
	stranger_enemy.threat[outsider.id] = 12.0
	server.zombies[stranger_enemy.id] = stranger_enemy
	t.eq(server.cmd_party_aid(101, 103, "bandage").get("reason"), "not_in_party",
		"invalid out-of-party treatment creates no threat")
	t.check(server.cmd_party_aid(101, 102, "bandage").get("ok", false),
		"real consumed medicine restores a wounded teammate")
	t.near(float(infected.threat.get(medic.id, 0.0)), 21.0, 0.001,
		"medic earns aggro from the actually restored 28 HP")
	t.check(not idle.threat.has(medic.id),
		"unengaged enemies remain unaware of silent medical actions")
	t.check(not stranger_enemy.threat.has(medic.id),
		"healing an ally cannot affect enemies engaged with unrelated players")
	var first_threat: float = float(infected.threat[medic.id])
	t.eq(server.cmd_party_aid(101, 102, "bandage").get("reason"), "cooldown",
		"replayed healing request is rejected")
	t.eq(float(infected.threat[medic.id]), first_threat,
		"replaying or rejecting a medical action cannot farm threat")
	infected.think_timer = 0.0
	server.tick_count = 2
	server._tick_zombies(0.1)
	t.eq(infected.target_id, medic.id,
		"healing threat can genuinely pull aggro from the injured frontliner")

	t.current = "wound treatment without healed health never attracts enemies"
	medic.party_aid_timer = 0.0
	fighter.survival.heal(100.0)
	fighter.survival.add_bleeding(25.0)
	var prior: float = float(infected.threat.get(medic.id, 0.0))
	t.check(server.cmd_party_aid(101, 102, "bandage").get("ok", false),
		"bandage can still treat a full-health bleeding patient")
	t.eq(float(infected.threat.get(medic.id, 0.0)), prior,
		"bleeding care alone adds zero new healer threat")
	t.current = "triage and restoration staff use one common aggro rule"
	var second = server.add_player(104, "Second")
	second.position = _at(world, 302.0, 302.0)
	t.check(server.cmd_party_invite(101, 104).get("ok", false), "second ally invited")
	t.check(server.cmd_party_accept(104).get("ok", false), "second ally joins")
	medic.inventory.add(PartyTriage.ITEM_ID, 1)
	medic.party_aid_timer = 0.0
	fighter.survival.hurt(50.0)
	second.survival.hurt(45.0)
	var triage_enemy := Zombie.new(server.new_id(), "walker", _at(world, 308.0, 301.0), -1)
	triage_enemy.target_id = fighter.id
	triage_enemy.threat[fighter.id] = 8.0
	server.zombies[triage_enemy.id] = triage_enemy
	t.check(server.cmd_party_triage(101).get("ok", false),
		"one real triage kit treats nearby injured allies")
	t.near(float(triage_enemy.threat.get(medic.id, 0.0)), 13.5, 0.001,
		"triage causes threat only for HP of its engaged patient, not strangers")
	medic.inventory.add("restoration_staff_1", 1)
	t.check(medic.inventory.equip("restoration_staff_1"), "medic equips real healing staff")
	medic.combat_energy = 100.0
	fighter.survival.hurt(25.0)
	second.survival.hurt(25.0)
	var staff_enemy := Zombie.new(server.new_id(), "walker", _at(world, 307.0, 303.0), -1)
	staff_enemy.target_id = fighter.id
	staff_enemy.threat[fighter.id] = 5.0
	staff_enemy.threat[second.id] = 5.0
	server.zombies[staff_enemy.id] = staff_enemy
	var response: Dictionary = server.cmd_skill(101, 1.0, 0.0)
	t.check(response.get("ok", false), "verified staff pulse heals actual party teammates")
	t.near(float(staff_enemy.threat.get(medic.id, 0.0)), 18.0, 0.001,
		"one multi-target pulse aggregates 24 HP once, for 18 threat")
	t.check(not server.snapshot_for(103)["you"].has("healing_threat"),
		"enemy hate tables remain private server state")
