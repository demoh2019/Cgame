extends RefCounted
## Equipment-based active skills must be validated and resolved on the server.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "weapon skills: unarmed and equipment gating"
	var world := WorldGen.new(2468)
	var server := GameServer.new(world, 27)
	var p = server.add_player(80, "SkillTester")
	t.eq(server.cmd_skill(80, 1.0, 0.0).get("reason"), "no_skill", "unarmed cannot use a club skill")
	t.near(p.combat_energy, Defs.COMBAT_ENERGY_MAX, 0.0001, "unarmed rejection does not cost energy")
	t.eq(server.cmd_skill(999, 1.0, 0.0).get("reason"), "dead", "unknown peer cannot use a skill")
	t.check(Combat.active_skill("pistol").is_empty(), "ranged weapons do not grant heavy melee attacks")
	t.check(Combat.active_skill("not_an_item").is_empty(), "unknown gear cannot grant an ability")

	p.inventory.add("club_2", 1)
	t.check(p.inventory.equip("club_2"), "equips a carried tier 2 club")
	t.eq(server.cmd_skill(80, 0.0, 0.0).get("reason"), "no_direction", "direction is validated")
	t.near(p.combat_energy, 100.0, 0.0001, "invalid direction has no energy cost")
	t.near(p.skill_timer, 0.0, 0.0001, "invalid direction does not start cooldown")

	t.current = "weapon skills: authoritative hit, cost and shared attack lock"
	p.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	var zombie := Zombie.new(server.new_id(), "brute", Vector3(202.0, world.height_at(202.0, 200.0), 200.0))
	server.zombies[zombie.id] = zombie
	var hp_before: float = zombie.health
	var strike: Dictionary = server.cmd_skill(80, 1.0, 0.0)
	t.check(strike.get("ok", false) and strike.get("hit", false), "server skill hits infected in range")
	t.eq(strike.get("target", ""), "zombie", "target is a zombie")
	t.near(zombie.health, hp_before - Combat.weapon_damage("club_2") * 1.6, 0.001, "server computes tiered skill damage")
	t.near(p.combat_energy, 70.0, 0.001, "server charges 30 energy")
	t.near(p.skill_timer, 6.0, 0.001, "server starts six second skill cooldown")
	t.eq(server.cmd_skill(80, 1.0, 0.0).get("reason"), "cooldown", "cannot spam active skill")
	t.eq(server.cmd_attack(80, 1.0, 0.0).get("reason"), "cooldown", "normal attacks share skill lock")
	t.near(p.combat_energy, 70.0, 0.001, "cooldown rejects without additional energy cost")
	var snap: Dictionary = server.snapshot_for(80)
	t.near(float(snap["you"]["combat_energy"]), 70.0, 0.001, "energy included in owner snapshot")
	t.near(float(snap["you"]["skill_cooldown"]), 6.0, 0.001, "cooldown included in owner snapshot")

	t.current = "weapon skills: regeneration, insufficient energy and loss of equipment"
	p.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	server.tick(1.0)
	t.near(p.combat_energy, 79.0, 0.001, "energy regenerates only on authoritative tick")
	t.near(p.skill_timer, 5.0, 0.001, "skill timer advances on authoritative tick")
	p.skill_timer = 0.0
	p.attack_timer = 0.0
	p.combat_energy = 29.0
	t.eq(server.cmd_skill(80, 1.0, 0.0).get("reason"), "no_energy", "insufficient energy rejects skill")
	t.near(p.combat_energy, 29.0, 0.001, "failed skill cannot spend energy")
	t.near(p.skill_timer, 0.0, 0.001, "failed skill cannot trigger cooldown")
	t.check(p.inventory.remove("club_2", 1), "can remove an equipped club")
	t.eq(server.cmd_skill(80, 1.0, 0.0).get("reason"), "no_skill", "ghost-equipped club cannot attack")
	t.near(p.combat_energy, 29.0, 0.001, "ghost weapon attempt cannot mint or spend energy")
	p.survival.hurt(1000.0)
	t.eq(server.cmd_skill(80, 1.0, 0.0).get("reason"), "dead", "dead players cannot use abilities")
	server._spawn_player(p)
	t.near(p.combat_energy, Defs.COMBAT_ENERGY_MAX, 0.001, "respawn refills combat energy")
	t.near(p.skill_timer, 0.0, 0.001, "respawn resets skill cooldown")

	t.current = "weapon skills: safe settlement retains PvP protection"
	var defender = server.add_player(81, "SafeDefender")
	p.inventory.add("club_1", 1)
	p.inventory.equip("club_1")
	p.position = Vector3(8.0, world.height_at(8.0, 0.0), 0.0)
	defender.position = Vector3(10.0, world.height_at(10.0, 0.0), 0.0)
	var health_before: float = defender.survival.health
	var safe_strike: Dictionary = server.cmd_skill(80, 1.0, 0.0)
	t.check(safe_strike.get("ok", false) and not safe_strike.get("hit", true), "swing in safe hub does not hit a player")
	t.near(defender.survival.health, health_before, 0.0001, "safe hub prevents skill PvP damage")
