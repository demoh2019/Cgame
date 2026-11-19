extends RefCounted
## Active mitigation only for successful, server-owned guardian taunts.
## Ordinary players, stale gear, dead players and PvP remain unchanged.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Guardian = preload("res://scripts/shared/guardian_taunt.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "bounded defensive damage reduction"
	t.near(Guardian.brace_damage(40.0, 3.0, true, true), 28.0, 0.001,
		"active frontline takes 30 percent less infected damage")
	t.near(Guardian.brace_damage(40.0, 0.0, true, true), 40.0, 0.001,
		"expired brace gives no damage reduction")
	t.near(Guardian.brace_damage(40.0, 3.0, false, true), 40.0, 0.001,
		"lost melee equipment cancels damage reduction")
	t.near(Guardian.brace_damage(40.0, 3.0, true, false), 40.0, 0.001,
		"disbanded party gets no frontline protection")
	t.near(Guardian.brace_damage(-3.0, 3.0, true, true), 0.0, 0.001,
		"negative damage never becomes healing")
	t.near(Guardian.brace_damage(INF, 3.0, true, true), 0.0, 0.001,
		"nonfinite input cannot cause infinite health loss")
	t.near(Guardian.brace_damage(25.0, NAN, true, true), 25.0, 0.001,
		"nonfinite brace cannot grant immunity")

	t.current = "taunt creates one short-lived guard"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 42)
	var tank = server.add_player(81, "Guardian")
	var ally = server.add_player(82, "Medic")
	tank.position = _at(world, 310, 0)
	ally.position = _at(world, 313, 0)
	var enemy = Zombie.new(server.new_id(), "brute", _at(world, 312, 0))
	enemy.state = Zombie.State.CHASE
	enemy.target_id = ally.id
	server.zombies[enemy.id] = enemy
	t.check(server.cmd_party_invite(81, 82).get("ok", false), "real party invited")
	t.check(server.cmd_party_accept(82).get("ok", false), "real party formed")
	tank.inventory.add("club_1", 1)
	t.check(tank.inventory.equip("club_1"), "real carried club equipped")
	var started: Dictionary = server.cmd_guardian_taunt(81)
	t.check(started.get("ok", false), "server confirms frontline provocation")
	t.near(tank.guardian_brace, Guardian.GUARD_SECONDS, 0.001,
		"successful taunt starts three seconds of brace")
	t.near(float(started.get("brace_seconds", 0.0)), Guardian.GUARD_SECONDS, 0.001,
		"acknowledgement reports finite brace lifetime")
	t.near(float(server.snapshot_for(81)["you"]["guardian_brace"]), Guardian.GUARD_SECONDS,
		0.001, "HUD lifetime is derived from server state")
	t.near(server._infected_damage_for(tank, 40.0), 28.0, 0.001,
		"shared melee and raid damage helper applies brace")
	t.near(server._infected_damage_for(ally, 40.0), 40.0, 0.001,
		"non-guardian party member does not gain a free shield")

	t.current = "real infected attack after armor"
	# Force one deterministic server zombie hit at close range.
	enemy.position = _at(world, 310.5, 0)
	enemy.target_id = 81
	enemy.state = Zombie.State.ATTACK
	enemy.think_timer = 1.0
	enemy.attack_timer = 0.0
	var hp: float = tank.survival.health
	server._tick_zombies(0.05)
	var expected: float = Combat.apply_armor(float(enemy.data["damage"]), "")
	expected *= 1.0 - Guardian.INFECTED_DAMAGE_REDUCTION
	t.near(tank.survival.health, hp - expected, 0.001,
		"actual zombie melee hit passes through defensive brace")
	t.near(enemy.forced_target_seconds, Guardian.FOCUS_SECONDS - 0.05, 0.06,
		"forced enemy focus continues through hit")

	t.current = "time and equipment invalidation"
	server._tick_players(Guardian.GUARD_SECONDS + 0.1)
	t.near(tank.guardian_brace, 0.0, 0.001, "brace expires with server time")
	t.near(server._infected_damage_for(tank, 40.0), 40.0, 0.001,
		"expired brace restores ordinary infected damage")
	tank.guardian_brace = Guardian.GUARD_SECONDS
	tank.inventory.remove("club_1", 1)
	t.near(server._infected_damage_for(tank, 40.0), 40.0, 0.001,
		"removing equipped weapon eliminates benefit immediately")
	server._tick_players(0.05)
	t.near(tank.guardian_brace, 0.0, 0.001,
		"invalid gear clears stored brace")
	tank.inventory.add("club_1", 1)
	tank.inventory.equip("club_1")
	tank.guardian_brace = 3.0
	t.check(server.cmd_party_leave(82).get("ok", false), "party disbands")
	t.near(server._infected_damage_for(tank, 40.0), 40.0, 0.001,
		"solo guardian gets no reduction")
	server._tick_players(0.05)
	t.near(tank.guardian_brace, 0.0, 0.001,
		"disband ends any unspent brace")
	tank.guardian_brace = 3.0
	tank.survival.hurt(999.0)
	server._on_player_death(tank, -enemy.id)
	t.near(tank.guardian_brace, 0.0, 0.001,
		"death removes brace instead of carrying invulnerability to respawn")
	server._spawn_player(tank)
	t.near(tank.guardian_brace, 0.0, 0.001,
		"respawn never starts protected")

	t.current = "no PvP or environmental protection"
	t.near(Combat.apply_armor(40.0, ""), 40.0, 0.001,
		"PvP damage processing retains normal armor-only path")
	t.near(tank.survival.warmth_seconds, 0.0, 0.001,
		"combat defensive brace cannot create environmental warmth")
