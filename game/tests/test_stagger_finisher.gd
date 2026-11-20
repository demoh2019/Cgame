extends RefCounted
## Strong melee bonus requires genuine owned weapon, front-facing stunned infected.
const Defs = preload("res://scripts/shared/defs.gd")
const Finisher = preload("res://scripts/shared/stagger_finisher.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	var world := WorldGen.new(2090)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(world)
	t.current = "weapon, status and world checks for PvE finisher"
	t.check(site.is_finite(), "clear dangerous-zone combat site")
	if not site.is_finite():
		return
	var sim := GameServer.new(world, 2090)
	var survivor = sim.add_player(91, "Fencer")
	survivor.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	survivor.yaw = PI * 0.5
	t.eq(sim.cmd_stagger_finisher(999).get("reason", ""), "dead",
		"nonexistent peer cannot force a melee finisher")
	t.eq(sim.cmd_stagger_finisher(91).get("reason", ""), "need_melee",
		"unarmed characters cannot spend energy for a finisher")
	survivor.inventory.add("club_1", 1)
	t.check(survivor.inventory.equip("club_1"), "real carried club equipped")
	var victim := Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 1.1, world.height_at(site.x + 1.1, site.y), site.y))
	sim.zombies[victim.id] = victim
	t.eq(sim.cmd_stagger_finisher(91).get("reason", ""), "no_staggered_target",
		"ordinary healthy infected cannot be executed")
	t.check(victim.apply_stagger(1.0), "stagger is applied server-side")
	survivor.yaw = -PI * 0.5
	t.check(not Finisher.eligible(world, survivor, victim),
		"finisher cannot strike behind the survivor")
	t.eq(sim.cmd_stagger_finisher(91).get("reason", ""), "no_staggered_target",
		"turning away cannot select the zombie")
	survivor.yaw = PI * 0.5
	var far: Vector3 = victim.position
	victim.position.x += 5.0
	t.check(not Finisher.eligible(world, survivor, victim),
		"cannot finish an enemy beyond equipped reach")
	victim.position = far
	var original_energy: float = survivor.combat_energy
	survivor.combat_energy = 23.0
	t.eq(sim.cmd_stagger_finisher(91).get("reason", ""), "no_energy",
		"energy below cost rejects without damage")
	t.eq(victim.stagger_seconds, 1.0, "rejected finisher preserves target stun")
	survivor.combat_energy = original_energy
	t.current = "valid stagger finishing blow is atomic"
	victim.health = 19.0
	var result: Dictionary = sim.cmd_stagger_finisher(91)
	t.check(bool(result.get("ok", false)), "melee player can finish real stunned infected")
	t.eq(int(result.get("target", -1)), victim.id,
		"server selects the actual nearby infected")
	t.check(bool(result.get("killed", false)), "damage kills weakened infected")
	t.check(not victim.is_alive(), "damage applied to authoritative zombie")
	t.near(survivor.combat_energy, original_energy - Finisher.ENERGY_COST,
		0.001, "exactly 24 combat energy consumed")
	t.eq(victim.stagger_seconds, 0.0, "stagger removed by the finisher")
	t.near(survivor.finisher_cooldown, Finisher.COOLDOWN_SECONDS,
		0.001, "server starts six-second cooldown")
	t.eq(survivor.kills, 1, "ordinary kill and loot pipeline credits the attacker")
	t.eq(sim.cmd_stagger_finisher(91).get("reason", ""), "cooldown",
		"cannot chain or duplicate a finisher while on cooldown")
	var event: Dictionary = {}
	for item in sim.events:
		if item.get("type", "") == "stagger_finisher":
			event = item
	t.check(not event.is_empty(), "private event announces finish")
	var net := Net.new()
	t.check(net._event_visible_to(event, 91), "finisher event visible to initiator")
	t.check(not net._event_visible_to(event, 92), "strangers cannot receive private event")
	net.free()
	t.current = "raid boss, lost weapon and respawn protection"
	survivor.finisher_cooldown = 0.0
	victim = Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 1.2, world.height_at(site.x + 1.2, site.y), site.y))
	victim.raid_boss = true
	victim.stagger_seconds = 1.0
	sim.zombies[victim.id] = victim
	t.check(not Finisher.eligible(world, survivor, victim),
		"even forged boss stun cannot unlock a raid-boss finisher")
	victim.raid_boss = false
	survivor.inventory.remove("club_1", 1)
	t.eq(sim.cmd_stagger_finisher(91).get("reason", ""), "need_melee",
		"removed equipped gear cannot authorize a melee finisher")
	survivor.inventory.add("club_1", 1)
	survivor.inventory.equip("club_1")
	survivor.finisher_cooldown = Finisher.COOLDOWN_SECONDS
	sim._tick_players(0.1)
	t.check(survivor.finisher_cooldown < Finisher.COOLDOWN_SECONDS,
		"server tick decreases transient cooldown")
	sim._spawn_player(survivor)
	t.eq(survivor.finisher_cooldown, 0.0, "respawn removes temporary combat timer")
