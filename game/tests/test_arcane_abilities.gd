extends RefCounted
## Classless Arcane Bolt and Cataclysm ultimate are server-owned, cost energy,
## respect cooldowns, and the ultimate never harms survivors.
const Arcane = preload("res://scripts/shared/arcane_abilities.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")


func _zombie(sim, world, x: float, z: float) -> Zombie:
	var zombie := Zombie.new(sim.new_id(), "walker", Vector3(x, world.height_at(x, z), z))
	sim.zombies[zombie.id] = zombie
	return zombie


func run(t) -> void:
	t.current = "damage formulas"
	t.near(Arcane.bolt_damage(0.0), Arcane.BOLT_BASE_DAMAGE, 0.0001, "bolt base damage")
	t.check(Arcane.bolt_damage(0.5) > Arcane.bolt_damage(0.0), "ranged training strengthens the bolt")
	t.near(Arcane.ultimate_damage(0.0, 0.0), Arcane.ULTIMATE_BASE_DAMAGE, 0.0001, "full damage at the centre")
	t.near(Arcane.ultimate_damage(Arcane.ULTIMATE_RADIUS, 0.0), Arcane.ULTIMATE_BASE_DAMAGE * 0.5, 0.0001, "half at the edge")
	t.eq(Arcane.ultimate_damage(Arcane.ULTIMATE_RADIUS + 0.1, 0.0), 0.0, "nothing outside the blast")

	var world := WorldGen.new(4412)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(world)
	t.check(site.is_finite(), "clear dangerous-zone combat site")
	if not site.is_finite():
		return
	var sim := GameServer.new(world, 4412)
	var caster = sim.add_player(31, "Mage")
	caster.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)

	t.current = "arcane bolt"
	t.eq(sim.cmd_arcane_bolt(999, 1, 0).get("reason", ""), "dead", "unknown peer cannot cast")
	t.eq(sim.cmd_arcane_bolt(31, 0, 0).get("reason", ""), "no_direction", "a bolt needs an aim")
	var target := _zombie(sim, world, site.x + 6.0, site.y)
	var health_before: float = target.health
	var energy_before: float = caster.combat_energy
	var bolt: Dictionary = sim.cmd_arcane_bolt(31, 1, 0)
	t.check(bool(bolt.get("ok", false)), "bolt casts")
	t.check(bool(bolt.get("hit", false)), "bolt hits the infected in its path")
	t.check(target.health < health_before, "bolt damages the infected")
	t.near(caster.combat_energy, energy_before - Arcane.BOLT_ENERGY_COST, 0.0001, "bolt costs energy")
	t.check(sim.events.any(func(e): return str(e.get("type", "")) == "arcane_bolt"), "bolt is broadcast for visuals")
	caster.attack_timer = 0.0
	t.eq(sim.cmd_arcane_bolt(31, 1, 0).get("reason", ""), "cooldown", "bolt has a cooldown")
	caster.arcane_cooldown = 0.0
	caster.combat_energy = Arcane.BOLT_ENERGY_COST - 1.0
	t.eq(sim.cmd_arcane_bolt(31, 1, 0).get("reason", ""), "no_energy", "bolt needs energy")

	t.current = "cataclysm ultimate"
	caster.combat_energy = 100.0
	caster.attack_timer = 0.0
	var near := _zombie(sim, world, site.x + 1.0, site.y + 1.0)
	var edge := _zombie(sim, world, site.x, site.y + Arcane.ULTIMATE_RADIUS - 0.5)
	var outside := _zombie(sim, world, site.x - Arcane.ULTIMATE_RADIUS - 3.0, site.y)
	var bystander = sim.add_player(32, "Bystander")
	bystander.position = caster.position + Vector3(1.0, 0.0, 0.0)
	var bystander_health: float = bystander.survival.health
	var near_before: float = near.health
	var edge_before: float = edge.health
	var outside_before: float = outside.health
	var ult: Dictionary = sim.cmd_ultimate(31)
	t.check(bool(ult.get("ok", false)), "ultimate casts")
	t.check(int(ult.get("hits", 0)) >= 2, "ultimate hits every infected in range")
	t.check(near.health < near_before or not near.is_alive(), "close infected hurt")
	t.check(edge.health < edge_before or not edge.is_alive(), "edge infected hurt")
	t.eq(outside.health, outside_before, "infected outside the blast untouched")
	t.eq(bystander.survival.health, bystander_health, "ultimate never damages survivors")
	t.near(caster.ultimate_cooldown, Arcane.ULTIMATE_COOLDOWN, 0.0001, "long cooldown starts")
	caster.attack_timer = 0.0
	t.eq(sim.cmd_ultimate(31).get("reason", ""), "cooldown", "ultimate cannot be spammed")
	caster.ultimate_cooldown = 0.0
	caster.combat_energy = Arcane.ULTIMATE_ENERGY_COST - 1.0
	t.eq(sim.cmd_ultimate(31).get("reason", ""), "no_energy", "ultimate needs energy")
	caster.mounted = true
	caster.combat_energy = 100.0
	t.eq(sim.cmd_ultimate(31).get("reason", ""), "mounted", "no ultimate from the saddle")
