extends RefCounted
## Server impact creates one unpersisted, enemy-bound, non-PvP counterstrike.

const MeleeParry = preload("res://scripts/shared/melee_parry.gd")
const Riposte = preload("res://scripts/shared/parry_riposte.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")


func run(t) -> void:
	t.current = "earned only after real melee parry"
	var world := WorldGen.new(2090)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(world)
	t.check(site.is_finite(), "combat has a traversable red-zone test site")
	if not site.is_finite():
		return
	var sim := GameServer.new(world, 2090)
	var fighter = sim.add_player(92, "Parry Fencer")
	fighter.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	fighter.yaw = PI / 2.0
	fighter.inventory.add("club_1", 1)
	t.check(fighter.inventory.equip("club_1"), "owns and equips melee club")
	var infected = Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 1.1, world.height_at(site.x + 1.1, site.y), site.y))
	infected.target_id = 92
	infected.state = Zombie.State.ATTACK
	infected.think_timer = 1.0
	sim.zombies[infected.id] = infected
	t.check(not Riposte.can_strike(fighter, infected, "club_1"),
		"mere ownership cannot create bonus")
	t.check(bool(sim.cmd_parry(92).get("ok", false)), "parry consumes stamina")
	t.eq(fighter.riposte_target_id, -1,
		"pressing parry never pre-arms a counter")
	sim._tick_zombies(0.05)
	t.eq(fighter.parry_window, 0.0, "impact consumes the defensive window")
	t.near(fighter.riposte_seconds, Riposte.WINDOW_SECONDS, 0.001,
		"confirmed hit starts short window")
	t.eq(fighter.riposte_target_id, infected.id,
		"the original attacker alone is eligible")
	t.check(Riposte.can_strike(fighter, infected, "club_1"),
		"normal follow-up can counter original enemy")
	var unrelated = Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 4.0, world.height_at(site.x + 4.0, site.y), site.y))
	t.check(not Riposte.can_strike(fighter, unrelated, "club_1"),
		"other infected cannot receive the damage bonus")
	t.check(not Riposte.can_strike(fighter, infected, "sword_1"),
		"other weapon cannot receive the bonus")
	infected.raid_boss = true
	t.check(not Riposte.can_strike(fighter, infected, "club_1"),
		"raid bosses remain immune")
	infected.raid_boss = false
	var saved: Dictionary = sim.character_data(fighter)
	t.check(not saved.has("riposte_seconds") and not saved.has("riposte_target_id"),
		"timing and enemy IDs never persist to Nakama")
	t.near(float(sim.snapshot_for(92)["you"]["riposte_seconds"]),
		Riposte.WINDOW_SECONDS, 0.001, "only owner sees remaining time")

	t.current = "first real melee hit consumes the buff and cannot crit-stack"
	sim._tick_players(MeleeParry.ATTACK_LOCK + 0.01)
	var hp: float = infected.health
	var strike: Dictionary = sim.cmd_attack(92, 1.0, 0.0)
	t.check(bool(strike.get("ok", false)) and bool(strike.get("riposte", false)),
		"original infected receives actual riposte")
	t.check(not bool(strike.get("crit", true)) and not bool(strike.get("ambush", true)),
		"counter never multiplies a crit or stealth opener")
	t.eq(fighter.riposte_seconds, 0.0, "single-use window consumed")
	t.eq(fighter.riposte_target_id, -1, "target is erased")
	var base_damage: float = Combat.weapon_damage("club_1")
	base_damage *= fighter.progression.combat_damage_multiplier("club_1")
	base_damage *= 1.0 + fighter.skills.bonus("melee_damage")
	base_damage = Combat.against_infected(base_damage, "club_1", true)
	base_damage *= 1.0 + fighter.skills.bonus("zombie_damage")
	t.near(hp - infected.health, base_damage * Riposte.DAMAGE_FACTOR, 0.05,
		"actual server hit has exactly the bounded PvE damage bonus")

	t.current = "misses, removed weapons, expiry and respawn clear the state"
	t.check(Riposte.arm(fighter, infected), "unit re-arm for miss test")
	fighter.attack_timer = 0.0
	var miss: Dictionary = sim.cmd_attack(92, -1.0, 0.0)
	t.check(bool(miss.get("ok", false)) and not bool(miss.get("hit", true)),
		"melee swing away from enemy misses normally")
	t.eq(fighter.riposte_target_id, -1, "miss consumes the opportunity")
	t.check(Riposte.arm(fighter, infected), "can arm again in isolation")
	fighter.inventory.remove("club_1", 1)
	Riposte.tick(fighter, 0.01)
	t.eq(fighter.riposte_seconds, 0.0, "lost weapon invalidates attack")
	fighter.inventory.add("club_1", 1)
	fighter.inventory.equip("club_1")
	t.check(Riposte.arm(fighter, infected), "owned club works again")
	Riposte.tick(fighter, Riposte.WINDOW_SECONDS)
	t.eq(fighter.riposte_target_id, -1, "server expiry destroys response")
	t.check(Riposte.arm(fighter, infected), "can arm before death")
	sim._spawn_player(fighter)
	t.eq(fighter.riposte_seconds, 0.0, "respawn never retains window")
	t.eq(fighter.riposte_target_id, -1, "respawn never retains enemy")
