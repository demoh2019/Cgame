extends RefCounted
## Infected pursuit, party support and stamina regeneration are private.
const CombatStress = preload("res://scripts/shared/combat_stress.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _place(world, actor, x: float, z: float) -> void:
	actor.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "only real chasing PvE threats produce stress"
	var server := GameServer.new(WorldGen.new(572), 572)
	var solo = server.add_player(11, "Solo")
	var ally = server.add_player(12, "Ally")
	var stranger = server.add_player(13, "Stranger")
	_place(server.world, solo, 270.0, 270.0)
	_place(server.world, ally, 273.0, 270.0)
	_place(server.world, stranger, 275.0, 270.0)
	var infected := Zombie.new(server.new_id(), "walker",
		Vector3(275.0, server.world.height_at(275, 270), 270.0))
	server.zombies[infected.id] = infected
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 0.0,
		"idle infected cannot generate stress")
	infected.target_id = solo.id
	infected.state = Zombie.State.CHASE
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 1.0,
		"real pursuing infected counts")
	t.eq(CombatStress.pressure(server.zombies, ally.id, ally.position), 0.0,
		"another player cannot inherit this zombie's pressure")
	infected.position.x = 310.0
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 0.0,
		"distant infected cannot keep pressure high")
	infected.position.x = 275.0
	infected.state = Zombie.State.INVESTIGATE
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 0.0,
		"no stress after infected loses target")
	infected.state = Zombie.State.CHASE
	infected.elite = true
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 1.5,
		"elite pursuit is more intimidating")
	infected.raid_boss = true
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 2.0,
		"raid boss produces extra pressure")
	infected.state = Zombie.State.DEAD
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 0.0,
		"defeated infected never continue stress")

	t.current = "corrupt or overflowing positions cannot create phantom PvE pressure"
	var valid_position: Vector3 = solo.position
	var valid_enemy_position: Vector3 = infected.position
	infected.state = Zombie.State.CHASE
	infected.raid_boss = false
	infected.elite = false
	infected.position = Vector3(1.0e30, 0.0, 0.0)
	t.eq(CombatStress.pressure(server.zombies, solo.id, solo.position), 0.0,
		"huge but finite enemy separation cannot register as nearby")
	infected.position = valid_enemy_position
	var poisoned: Dictionary = {999: null, infected.id: infected}
	t.eq(CombatStress.pressure(poisoned, solo.id, valid_position), 1.0,
		"null zombie records cannot break an otherwise valid pressure scan")
	infected.state = Zombie.State.DEAD

	t.current = "stress rate bounds and recovery"
	t.near(CombatStress.advance(0.0, 10.0, 1.0, false, false, false),
		50.0, 0.001, "solo pursuit builds pressure")
	t.near(CombatStress.advance(0.0, 10.0, 1.0, false, false, true),
		30.0, 0.001, "nearby living squad member dampens growth")
	t.near(CombatStress.advance(98.0, 100.0, 2.0, false, false, false),
		100.0, 0.001, "stress cannot exceed cap")
	t.near(CombatStress.advance(60.0, 3.0, 0.0, false, true, false),
		45.0, 0.001, "shelter speeds recovery")
	t.near(CombatStress.advance(60.0, 3.0, 0.0, true, false, false),
		30.0, 0.001, "hub rapidly clears fear")
	t.near(CombatStress.advance(15.0, 15.0, 0.0, false, false, false),
		0.0, 0.001, "calm field travel recovers over time")
	t.near(CombatStress.regen_multiplier(0.0), 1.0, 0.001,
		"calm survivor has normal passive regen")
	t.near(CombatStress.regen_multiplier(100.0), 0.6, 0.001,
		"max penalty is capped at forty percent")
	t.near(CombatStress.regen_multiplier(NAN), 1.0, 0.001,
		"invalid stress cannot produce NaN stamina")
	t.near(CombatStress.advance(50.0, NAN, 1.0, false, false, false),
		50.0, 0.001, "invalid time cannot change stress")

	t.current = "server-only team support and private stamina changes"
	infected.state = Zombie.State.CHASE
	infected.elite = false
	infected.raid_boss = false
	solo.survival.stamina = 20.0
	solo.survival.stamina_recovery_delay = 0.0
	t.check(not CombatStress.has_live_companion(solo.id, solo.position,
		server.players, server.parties), "a nearby stranger does not count as support")
	t.check(bool(server.cmd_party_invite(11, 12).get("ok", false)),
		"survivor forms actual group")
	t.check(bool(server.cmd_party_accept(12).get("ok", false)),
		"companion joins")
	t.check(CombatStress.has_live_companion(solo.id, solo.position,
		server.players, server.parties), "real nearby teammate grants support")
	var original_ally_position: Vector3 = ally.position
	ally.position = Vector3(1.0e30, 0.0, 0.0)
	t.check(not CombatStress.has_live_companion(solo.id, solo.position,
		server.players, server.parties),
		"overflowing party separation never grants fake combat support")
	ally.position = original_ally_position
	t.check(CombatStress.has_live_companion(solo.id, solo.position,
		server.players, server.parties),
		"real nearby ally support returns after a valid position update")
	infected.target_id = solo.id
	solo.combat_stress = 80.0
	var stamina_before: float = solo.survival.stamina
	server._tick_players(1.0)
	t.check(solo.combat_stress > 80.0,
		"confirmed infected chase raises authoritative stress despite teammate")
	t.check(solo.survival.stamina > stamina_before,
		"passive stamina still recovers under stress, not a hard disable")
	t.check(float(server.snapshot_for(11)["you"]["combat_stress"]) > 80.0,
		"owner receives live stress meter")
	t.eq(float(server.snapshot_for(13)["you"]["combat_stress"]), 0.0,
		"unrelated client has no copy of survivor's stress")
	# Stress only throttles natural regen; health is unaffected by the meter.
	t.near(solo.survival.health, solo.survival.max_health, 0.001,
		"combat stress itself does not cause damage")
	infected.state = Zombie.State.INVESTIGATE
	server._tick_players(1.0)
	t.check(solo.combat_stress < 90.0,
		"losing chase lets stress start recovering")
	_place(server.world, solo, 0.0, 0.0)
	server._tick_players(1.0)
	t.check(solo.combat_stress < 80.0,
		"safe settlement accelerates stress recovery")
	solo.survival.health = 0.0
	server._on_player_death(solo, -1)
	t.eq(solo.combat_stress, 0.0, "death clears ephemeral stress")
