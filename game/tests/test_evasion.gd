extends RefCounted
## Server-authoritative combat evasion: stamina, collision, PvP and infected wounds.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Evasion = preload("res://scripts/shared/evasion.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _clear_red_zone_spot(world) -> Vector2:
	# Avoid procedural terrain/water so the exercise does not depend on a lucky seed.
	for x in range(730, 900, 12):
		for z in range(65, 210, 12):
			if world.is_water(float(x), float(z)):
				continue
			if world.blockers_near(float(x), float(z), 6.0).is_empty():
				return Vector2(float(x), float(z))
	return Vector2(INF, INF)


func run(t) -> void:
	var world := WorldGen.new(2090)
	var site: Vector2 = _clear_red_zone_spot(world)
	t.current = "dodge collision and direction validation"
	t.check(site.is_finite(), "found an unobstructed land site in PvP territory")
	if not site.is_finite():
		return
	t.check(world.zone_at(site.x, site.y) >= 2, "testing a red/black PvP zone")
	var server := GameServer.new(world, 2090)
	var player = server.add_player(91, "Scout")
	var origin := Vector3(site.x, world.height_at(site.x, site.y), site.y)
	player.position = origin
	t.eq(server.cmd_dodge(91, NAN, 0.0).get("reason", ""), "no_direction",
		"NaN direction is rejected")
	t.eq(server.cmd_dodge(91, INF, 0.0).get("reason", ""), "no_direction",
		"infinite direction is rejected")
	t.eq(server.cmd_dodge(91, 0.0, 0.0).get("reason", ""), "no_direction",
		"zero direction is rejected")
	t.eq(server.cmd_dodge(91, 1e300, 0.0).get("reason", ""), "no_direction",
		"finite vector with overflowing magnitude is rejected")
	t.near(player.survival.stamina, Defs.MAX_STAMINA, 0.001,
		"invalid directions cannot spend stamina")
	t.near(player.dodge_timer, 0.0, 0.001, "invalid input cannot set cooldown")
	t.check(Evasion.moved_distance(origin, Evasion.destination(world, origin, Vector2(9999, 0)))
		<= Evasion.SPEED * Evasion.STEP * Evasion.STEPS + 0.001,
		"forged large direction cannot extend dash distance")

	t.current = "dodge stamina, cooldown, attack lock and server snapshots"
	var result: Dictionary = server.cmd_dodge(91, 1.0, 0.0)
	t.check(result.get("ok", false), "a rested player dodges across clear land")
	t.near(Evasion.moved_distance(origin, player.position), 2.56, 0.05,
		"server grants a fixed 2.56 meter sidestep")
	t.near(player.survival.stamina, 76.0, 0.001, "dodge consumes 24 stamina")
	t.near(player.dodge_timer, Evasion.COOLDOWN, 0.001, "cooldown starts on the server")
	t.near(player.dodge_immunity, Evasion.INVULNERABLE_TO_INFECTED, 0.001,
		"short infected avoidance starts on the server")
	t.eq(server.cmd_dodge(91, 1.0, 0.0).get("reason", ""), "cooldown",
		"spamming the dash cannot increase travel distance")
	t.eq(server.cmd_attack(91, 1.0, 0.0).get("reason", ""), "cooldown",
		"dodge interrupts immediate weapon swings")
	t.near(player.survival.stamina, 76.0, 0.001, "rejected repeat dash has no cost")
	var snap: Dictionary = server.snapshot_for(91)
	t.near(float(snap["you"]["dodge_cooldown"]), Evasion.COOLDOWN, 0.001,
		"owner snapshot displays dodge cooldown")
	t.near(float(snap["you"]["stamina"]), 76.0, 0.001, "owner sees consumed stamina")
	server._tick_players(0.1)
	t.check(player.dodge_timer < Evasion.COOLDOWN and player.dodge_timer > 0.0,
		"the authoritative tick decreases cooldown")
	t.check(player.dodge_immunity > 0.0, "brief protection is active during the dash")

	t.current = "dodge stops infected attacks but not PvP damage"
	var infected := Zombie.new(server.new_id(), "walker",
		Vector3(player.position.x + 1.1, world.height_at(player.position.x + 1.1, player.position.z),
			player.position.z))
	infected.target_id = 91
	infected.state = Zombie.State.ATTACK
	infected.think_timer = 1.0
	server.zombies[infected.id] = infected
	var hp: float = player.survival.health
	server._tick_zombies(0.05)
	t.near(player.survival.health, hp, 0.001, "infected blow is evaded")
	t.near(player.survival.infection, 0.0, 0.001, "evaded bite cannot transmit infection")
	var avoided := false
	for event in server.events:
		if event.get("type") == "evaded" and event.get("peer") == 91:
			avoided = true
	t.check(avoided, "server announces an evaded infected strike")
	player.dodge_immunity = 0.0
	infected.attack_timer = 0.0
	server._tick_zombies(0.05)
	t.check(player.survival.health < hp, "infected can hit after protection ends")
	t.check(player.survival.infection > 0.0, "unprotected zombie bite infects")

	var rival = server.add_player(92, "Raider")
	rival.inventory.add("club_1", 1)
	rival.inventory.equip("club_1")
	rival.position = Vector3(player.position.x - 1.5,
		world.height_at(player.position.x - 1.5, player.position.z), player.position.z)
	player.survival.health = 100.0
	player.dodge_immunity = Evasion.INVULNERABLE_TO_INFECTED
	var strike: Dictionary = server.cmd_attack(92, 1.0, 0.0)
	t.check(strike.get("ok", false) and strike.get("hit", false),
		"PvP attacks still connect with an evading survivor")
	t.check(player.survival.health < 100.0, "dodge does not grant PvP immunity")

	t.current = "dodge rejects overweight, exhaustion, and blocked routes atomically"
	player.dodge_timer = 0.0
	player.attack_timer = 0.0
	player.survival.stamina = 23.0
	t.eq(server.cmd_dodge(91, 1.0, 0.0).get("reason", ""), "no_stamina",
		"cannot dodge without 24 stamina")
	t.near(player.survival.stamina, 23.0, 0.001, "failed dodge preserves stamina")
	player.survival.stamina = 100.0
	player.survival.thirst = 2.0
	t.eq(server.cmd_dodge(91, 1.0, 0.0).get("reason", ""), "exhausted",
		"dehydrated survivor cannot evade")
	player.survival.thirst = 100.0
	player.inventory.add("stone_1", 90)
	t.check(player.inventory.movement_factor() < 1.0,
		"carried ore/stone causes meaningful encumbrance")
	t.eq(server.cmd_dodge(91, 1.0, 0.0).get("reason", ""), "overweight",
		"overweight players cannot use mobility to bypass cargo penalties")
	player.inventory.remove("stone_1", 90)
	player.position = origin
	world.add_dynamic_blocker(987654, origin.x + 1.5, origin.z, 0.9)
	var stamina_before: float = player.survival.stamina
	var blocked: Dictionary = server.cmd_dodge(91, 1.0, 0.0)
	t.eq(blocked.get("reason", ""), "blocked", "barricade stops the dodge")
	t.near(Evasion.moved_distance(origin, player.position), 0.0, 0.001,
		"stepwise movement cannot tunnel through a structure")
	t.near(player.survival.stamina, stamina_before, 0.001,
		"blocked dodge does not consume stamina")
	t.near(player.dodge_timer, 0.0, 0.001,
		"blocked dodge does not start cooldown")
	world.remove_dynamic_blocker(987654)
	player.survival.hurt(1000.0)
	t.eq(server.cmd_dodge(91, 1.0, 0.0).get("reason", ""), "dead",
		"dead players cannot dodge")
	server._spawn_player(player)
	t.near(player.dodge_timer, 0.0, 0.001, "respawn clears dodge cooldown")
	t.near(player.dodge_immunity, 0.0, 0.001, "respawn clears temporary protection")
	t.near(player.survival.stamina, Defs.MAX_STAMINA, 0.001,
		"respawn restores stamina")
