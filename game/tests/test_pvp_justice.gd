extends RefCounted
## Legal combat decisions use confirmed hits and trusted server state.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Law = preload("res://scripts/shared/pvp_infamy.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, player, x: float, z: float) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func _strike(sim, peer: int, direction: float) -> Dictionary:
	sim.players[peer].attack_timer = 0.0
	return sim.cmd_attack(peer, direction, 0.0)


func run(t) -> void:
	t.current = "legal rule boundaries"
	t.eq(Law.lawful_kill_reason(50.0, -1, 0.0, 3, 10.0), "outlaw",
		"outlaw may be hunted without criminal penalty")
	t.eq(Law.lawful_kill_reason(49.99, -1, 0.0, 3, 10.0), "",
		"non-outlaw still has protection")
	t.eq(Law.lawful_kill_reason(0.0, 3, 30.0, 3, 12.0), "self_defense",
		"genuine matching aggression justifies retaliation")
	t.eq(Law.lawful_kill_reason(0.0, 3, 30.0, 4, 12.0), "",
		"right cannot be spent against a bystander")
	t.eq(Law.lawful_kill_reason(0.0, 3, 30.0, 3, 30.0), "",
		"expired right is no longer valid")
	t.near(Law.defense_remaining(3, INF, 0.0), 0.0, 0.001,
		"invalid expiry never grants endless immunity")

	t.current = "live PvP retaliation"
	var world := WorldGen.new(32)
	var sim := Server.new(world, 32)
	var aggressor = sim.add_player(101, "Aggressor")
	var defender = sim.add_player(102, "Defender")
	var outlaw = sim.add_player(103, "Outlaw")
	for member in [aggressor, defender, outlaw]:
		member.inventory.add("club_1", 1)
		member.inventory.equip("club_1")
	_at(world, aggressor, 800, 0)
	_at(world, defender, 801.5, 0)
	_at(world, outlaw, 812, 0)
	var actual: Dictionary = _strike(sim, 101, 1.0)
	t.check(actual.get("ok", false) and actual.get("hit", false), "server accepts dangerous-zone attack")
	t.eq(defender.defense_target, 101, "only confirmed aggressor creates response window")
	t.near(float(sim.snapshot_for(102)["you"]["self_defense_seconds"]), 30.0, 0.001,
		"victim receives private response timer")
	t.near(float(sim.snapshot_for(103)["you"]["self_defense_seconds"]), 0.0, 0.001,
		"other players do not inherit defense rights")
	var alerts: Array = sim.events.filter(func(e): return e.get("type", "") == "self_defense")
	t.eq(alerts.size(), 1, "only first hit announces lawful response")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(alerts[0], 102), "defender sees private announcement")
	t.check(not net._event_visible_to(alerts[0], 103), "bystander cannot spy on right")
	net.free()
	_strike(sim, 102, -1.0)
	t.eq(aggressor.defense_target, -1, "first aggressor cannot claim counterattack protection")
	aggressor.survival.hurt(92.0)
	_strike(sim, 102, -1.0)
	t.check(not aggressor.survival.alive, "legitimate defender wins combat")
	t.near(defender.pvp_infamy, 0.0, 0.001, "self-defense adds no criminal reputation")
	t.eq(defender.kills, 1, "ordinary kill credit remains")
	var lawful: Array = sim.events.filter(func(e): return e.get("type", "") == "justice")
	t.eq(lawful.size(), 1, "defense generates one private lawful victory notice")

	t.current = "outlaw justice and normal crime"
	_at(world, outlaw, 803, 0)
	outlaw.pvp_infamy = 50.0
	outlaw.survival.hurt(95.0)
	_strike(sim, 102, 1.0)
	t.check(not outlaw.survival.alive, "outlaw is killed in dangerous zone")
	t.near(defender.pvp_infamy, 0.0, 0.001, "outlaw kill carries no criminal penalty")
	var neutral = sim.add_player(104, "Neutral")
	neutral.inventory.add("club_1", 1)
	neutral.inventory.equip("club_1")
	_at(world, neutral, 803, 0)
	neutral.survival.hurt(95.0)
	_strike(sim, 102, 1.0)
	t.check(not neutral.survival.alive, "normal unprovoked kill still works")
	t.near(defender.pvp_infamy, 25.0, 0.001, "ordinary lethal PvP still adds 25 infamy")
	_strike(sim, 102, 1.0)
	t.near(defender.pvp_infamy, 25.0, 0.001, "corpse replay does not duplicate score")

	t.current = "expiry, disconnect and safe-zone rejection"
	var raider = sim.add_player(105, "Raider")
	raider.inventory.add("club_1", 1)
	raider.inventory.equip("club_1")
	_at(world, raider, 800, 0)
	_at(world, defender, 801.5, 0)
	_strike(sim, 105, 1.0)
	t.eq(defender.defense_target, 105, "new valid attack grants new response right")
	sim.time += 30.1
	t.near(float(sim.snapshot_for(102)["you"]["self_defense_seconds"]), 0.0, 0.001,
		"right expires on authoritative clock")
	_strike(sim, 105, 1.0)
	sim.remove_player(105)
	t.eq(defender.defense_target, -1, "disconnected attacker loses target identity")
	var newcomer = sim.add_player(105, "FreshAccount")
	_at(world, newcomer, 10, 0)
	_at(world, defender, 11.5, 0)
	_strike(sim, 105, 1.0)
	t.eq(defender.defense_target, -1, "safe-zone attack creates no legal right")
	t.near(float(sim.snapshot_for(102)["you"]["self_defense_seconds"]), 0.0,
		0.001, "reused network ID cannot inherit stale combat guilt")
	var saved: Dictionary = sim.character_data(defender)
	t.check(not saved.has("defense_target") and not saved.has("defense_until"),
		"temporary combat rights are never persisted")
