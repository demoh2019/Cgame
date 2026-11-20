extends RefCounted
## Authentic infected melee protection, not an arbitrary client-authored shield.
## Simulates real zombie think-hit processing and existing PvE damage/respawn.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const GuardianIntercept = preload("res://scripts/shared/guardian_intercept.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "guardian interception rejects forged or unavailable protection"
	t.near(GuardianIntercept.damage(26.0), 16.9, 0.001,
		"guardian absorbs 65% of the enemy's original melee hit before armor")
	t.near(GuardianIntercept.damage(INF), 0.0, 0.001,
		"nonfinite damage cannot hurt guardian")
	t.near(GuardianIntercept.damage(-10.0), 0.0, 0.001,
		"invalid negative melee hit cannot heal")
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var tank = sim.add_player(41, "Guardian")
	var ally = sim.add_player(42, "Medic")
	var stranger = sim.add_player(43, "Stranger")
	tank.position = _at(world, 310.0, 0.0)
	ally.position = _at(world, 313.0, 0.0)
	stranger.position = _at(world, 311.5, 0.0)
	var enemy = Zombie.new(sim.new_id(), "brute", _at(world, 312.0, 0.0))
	enemy.target_id = ally.id
	enemy.state = Zombie.State.ATTACK
	enemy.think_timer = 1.0
	enemy.attack_timer = 0.0
	sim.zombies[enemy.id] = enemy
	t.eq(sim.cmd_guardian_intercept(41, 41).get("reason", ""), "self",
		"self-interception is not allowed")
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""), "not_in_party",
		"cannot protect an unrelated player")
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "tank invites real ally")
	t.check(sim.cmd_party_accept(42).get("ok", false), "ally forms party")
	t.eq(sim.cmd_guardian_intercept(41, 43).get("reason", ""), "not_in_party",
		"bystander is not an eligible ally")
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""), "need_melee",
		"unarmed player cannot cast a guardian link")
	tank.inventory.add("club_1", 1)
	t.check(tank.inventory.equip("club_1"), "guardian owns equipped melee weapon")
	t.eq(sim.cmd_guardian_intercept(41, 9999).get("reason", ""), "invalid_target",
		"unregistered target cannot create a free shield")
	ally.position = _at(world, 319.0, 0.0)
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""),
		"too_far_or_unsafe", "cannot guard ally beyond 4.5 metres")
	ally.position = Vector3(313.0, tank.position.y + GuardianIntercept.MAX_HEIGHT + 1.0, 0.0)
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""),
		"too_far_or_unsafe", "guardian cannot intercept blows on another floor")
	ally.position = _at(world, 313.0, 0.0)
	tank.combat_energy = 0.0
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""), "no_energy",
		"zero combat energy cannot arm the link")
	t.near(tank.guard_link_cooldown, 0.0, 0.001,
		"rejected link never starts the cooldown")

	t.current = "authentic one-shot hit routing on the zombie melee branch"
	tank.combat_energy = 100.0
	var cast: Dictionary = sim.cmd_guardian_intercept(41, 42)
	t.check(bool(cast.get("ok", false)), "guardian arms one nearby ally link")
	t.near(tank.combat_energy, 100.0 - GuardianIntercept.ENERGY_COST, 0.001,
		"exactly 20 combat energy spent on successful cast")
	t.near(tank.guard_link_seconds, GuardianIntercept.DURATION, 0.001,
		"server arms a bounded 9-second protection window")
	t.near(tank.guard_link_cooldown, GuardianIntercept.COOLDOWN, 0.001,
		"server enforces the full 28-second cooldown")
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""), "already_guarding",
		"duplicate command cannot stack defensive links")
	t.near(tank.combat_energy, 80.0, 0.001,
		"rejected duplicate never spends another energy charge")
	t.eq(int(sim.snapshot_for(41)["you"]["guardian_intercept_target"]), 42,
		"guardian receives only their private chosen target ID")
	t.eq(int(sim.snapshot_for(42)["you"]["guardian_guarded_by"]), 41,
		"protected player can see their current guardian")
	t.near(float(sim.snapshot_for(42)["you"]["guardian_guarded_seconds"]),
		GuardianIntercept.DURATION, 0.001,
		"protected player's shield countdown is server-authored")
	t.eq(int(sim.snapshot_for(43)["you"]["guardian_guarded_by"]), -1,
		"unrelated observer receives no protection relationship")

	var before_ally: float = ally.survival.health
	var before_tank: float = tank.survival.health
	sim._tick_zombies(0.05)
	t.near(ally.survival.health, before_ally, 0.001,
		"real infected melee strike is fully intercepted before secondary wounds")
	t.near(tank.survival.health,
		before_tank - GuardianIntercept.damage(float(enemy.data["damage"])), 0.001,
		"guardian takes only 65% of the original unarmored strike")
	t.near(tank.guard_link_seconds, 0.0, 0.001,
		"one intercepted hit immediately spends the protection")
	t.eq(tank.guard_link_target, -1, "link no longer points to a target after blocking")
	t.near(ally.survival.bleeding, 0.0, 0.001,
		"protected player avoids secondary melee wounds")
	var intercept_events: Array = sim.events.filter(
		func(e): return str(e.get("type", "")) == "guardian_intercept")
	t.eq(intercept_events.size(), 1, "exactly one intercept event emitted")
	if intercept_events.size() > 0:
		t.eq(int(intercept_events[0]["peer"]), ally.id, "event names the guarded ally")
		t.eq(int(intercept_events[0]["by"]), tank.id, "event identifies the real tank")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_guardian_intercept"), "network RPC exists")
	if intercept_events.size() > 0:
		t.check(net._event_visible_to(intercept_events[0], tank.id),
			"guardian receives a private intercept confirmation")
		t.check(net._event_visible_to(intercept_events[0], ally.id),
			"protected member receives a private intercept confirmation")
		t.check(not net._event_visible_to(intercept_events[0], stranger.id),
			"strangers never receive a private party interception event")
	net.free()

	t.current = "replay, expiry, weapon loss and party changes cannot create invulnerability"
	enemy.attack_timer = 0.0
	enemy.think_timer = 1.0
	enemy.target_id = ally.id
	enemy.state = Zombie.State.ATTACK
	sim._tick_zombies(0.05)
	t.check(ally.survival.health < before_ally,
		"the second real infected melee hit hurts the ally normally")
	t.eq(sim.events.filter(
		func(e): return str(e.get("type", "")) == "guardian_intercept").size(), 1,
		"one link cannot intercept a second hit")
	t.eq(sim.cmd_guardian_intercept(41, 42).get("reason", ""), "cooldown",
		"trying to recast after the block cannot bypass cooldown")
	tank.guard_link_cooldown = 0.0
	t.check(sim.cmd_guardian_intercept(41, 42).get("ok", false),
		"guardian can eventually rearm after cooldown")
	tank.inventory.remove("club_1", 1)
	t.check(not GuardianIntercept.can_intercept(tank, ally, sim.parties, world),
		"loss of the actual melee weapon immediately cancels hit protection")
	sim._tick_players(0.1)
	t.near(tank.guard_link_seconds, 0.0, 0.001,
		"server clears obsolete link automatically")
	tank.inventory.add("club_1", 1)
	tank.inventory.equip("club_1")
	tank.guard_link_cooldown = 0.0
	t.check(sim.cmd_guardian_intercept(41, 42).get("ok", false),
		"new link succeeds only after correct equipment restored")
	t.check(sim.cmd_party_leave(42).get("ok", false), "ally leaves the actual group")
	t.check(not GuardianIntercept.can_intercept(tank, ally, sim.parties, world),
		"disbanding the party eliminates protection without a new attack")
	sim._tick_players(0.1)
	t.near(tank.guard_link_seconds, 0.0, 0.001,
		"the simulation prunes links to former allies")
	t.eq(int(sim.snapshot_for(42)["you"]["guardian_guarded_by"]), -1,
		"former ally does not retain a stale guardian ID")

	t.current = "death and respawn never carry immunity"
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "party can reform")
	t.check(sim.cmd_party_accept(42).get("ok", false), "ally rejoins")
	tank.guard_link_cooldown = 0.0
	t.check(sim.cmd_guardian_intercept(41, 42).get("ok", false),
		"last guarded link is genuinely active")
	tank.survival.hurt(999.0)
	sim._on_player_death(tank, -enemy.id)
	t.near(tank.guard_link_seconds, 0.0, 0.001,
		"guardian death deletes any unspent link")
	t.eq(int(sim.snapshot_for(42)["you"]["guardian_guarded_by"]), -1,
		"the ally no longer sees a deceased guardian")
	sim._spawn_player(tank)
	t.near(tank.guard_link_seconds, 0.0, 0.001,
		"respawn does not re-arm any PvE invulnerability")
