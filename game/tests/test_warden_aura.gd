extends RefCounted
## Live group protection: real infected hit, real equipped two-piece set,
## nearby party checks, no stacking, no ghost gear and unchanged PvP.
const Defs = preload("res://scripts/shared/defs.gd")
const WardenAura = preload("res://scripts/shared/warden_aura.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Combat = preload("res://scripts/shared/combat.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _hit(sim, victim) -> void:
	sim.zombies.clear()
	victim.survival.reset()
	var infected := Zombie.new(sim.new_id(), "walker",
		victim.position + Vector3(1.1, 0.0, 0.0))
	infected.state = Zombie.State.ATTACK
	infected.target_id = victim.id
	sim.zombies[infected.id] = infected
	sim._tick_zombies(0.1)


func run(t) -> void:
	t.current = "party guardian must actually wear both rare pieces"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var guardian = sim.add_player(701, "Relic Guardian")
	var ally = sim.add_player(702, "Survivor")
	var second = sim.add_player(703, "Other Guardian")
	guardian.position = _at(world, 310.0, 0.0)
	ally.position = _at(world, 312.0, 0.0)
	second.position = _at(world, 313.0, 0.0)
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"solo recipient cannot receive another player's buff")
	t.check(sim.cmd_party_invite(701, 702).get("ok", false), "guardian invites nearby survivor")
	t.check(sim.cmd_party_accept(702).get("ok", false), "survivor joins the actual party")
	t.check(sim.cmd_party_invite(701, 703).get("ok", false), "guardian invites second player")
	t.check(sim.cmd_party_accept(703).get("ok", false), "second player joins the party")
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"unarmed guardian cannot protect party")
	guardian.inventory.add(WardenAura.ARMOR_ID, 1)
	guardian.inventory.equip(WardenAura.ARMOR_ID)
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"jacket without relic weapon does not activate the set")
	guardian.inventory.add(WardenAura.WEAPON_ID, 1)
	guardian.inventory.equip(WardenAura.WEAPON_ID)
	t.check(WardenAura.active_for(ally, sim.players, sim.parties, world),
		"both equipped and carried set pieces activate ally ward")
	t.check(not WardenAura.active_for(guardian, sim.players, sim.parties, world),
		"a solo set wearer does not gain their own extra party ward")
	t.check(sim.snapshot_for(702)["you"]["warden_ward"],
		"only server provides HUD ward status for the protected recipient")
	t.check(not sim.snapshot_for(701)["you"]["warden_ward"],
		"self cannot forge active ward through a client snapshot")

	t.current = "live server zombie hits apply bounded secondary protection"
	_hit(sim, ally)
	t.near(ally.survival.infection, 8.0 * 0.85, 0.001,
		"party ward reduces real walker infection by 15 percent")
	t.near(ally.survival.bleeding, 9.0 * 0.85, 0.001,
		"party ward reduces real walker bleeding by 15 percent")
	t.near(ally.survival.health, Defs.MAX_HEALTH - 9.0, 0.001,
		"aura never reduces direct damage or makes PvE invulnerable")
	second.inventory.add(WardenAura.ARMOR_ID, 1)
	second.inventory.add(WardenAura.WEAPON_ID, 1)
	second.inventory.equip(WardenAura.ARMOR_ID)
	second.inventory.equip(WardenAura.WEAPON_ID)
	_hit(sim, ally)
	t.near(ally.survival.infection, 8.0 * 0.85, 0.001,
		"two nearby guardians never stack the ward")
	t.near(ally.survival.bleeding, 9.0 * 0.85, 0.001,
		"two guardians cannot amplify a wound resistance exploit")

	t.current = "distance, set ownership, party and life are authoritative"
	second.position = _at(world, 400.0, 0.0)
	guardian.position = _at(world, 322.5, 0.0)
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"guardians outside eight metres give no protection")
	_hit(sim, ally)
	t.near(ally.survival.infection, 8.0, 0.001,
		"remote relic sets do not prevent infection")
	guardian.position = _at(world, 310.0, 0.0)
	guardian.inventory.remove(WardenAura.WEAPON_ID, 1)
	guardian.inventory.weapon = WardenAura.WEAPON_ID
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"stale equipment slot after dropping weapon gives no aura")
	guardian.inventory.add(WardenAura.WEAPON_ID, 1)
	guardian.inventory.equip(WardenAura.WEAPON_ID)
	guardian.survival.hurt(1000.0)
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"dead guardians provide no protection")
	guardian.survival.reset()
	guardian.position = _at(world, 0.0, 0.0)
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"set wearers in the safe hub cannot project the ward remotely")
	guardian.position = _at(world, 310.0, 0.0)
	t.check(WardenAura.active_for(ally, sim.players, sim.parties, world),
		"ward resumes with a living, equipped nearby party member")
	sim.cmd_party_leave(702)
	t.check(not WardenAura.active_for(ally, sim.players, sim.parties, world),
		"leaving the party instantly removes the bonus")

	t.current = "PvP damage and bleeding never receive infected-only protection"
	var rival = sim.add_player(704, "Enemy")
	guardian.position = _at(world, 800.0, 800.0)
	ally.position = _at(world, 801.0, 800.0)
	rival.position = _at(world, 802.0, 800.0)
	sim.cmd_party_invite(701, 702)
	sim.cmd_party_accept(702)
	t.check(WardenAura.active_for(ally, sim.players, sim.parties, world),
		"pvp zone alone does not disable infection protection for PvE")
	ally.survival.reset()
	rival.inventory.add("club_1", 1)
	rival.inventory.equip("club_1")
	sim._damage_target(rival, {"kind": "player", "id": 702}, 20.0)
	t.near(ally.survival.bleeding, Defs.PVP_MELEE_BLEEDING_PER_HIT, 0.001,
		"PvP wounds do not receive a guardian's infected-only reduction")
	t.near(ally.survival.health, Defs.MAX_HEALTH - Combat.apply_armor(20.0, ""),
		0.001, "PvP uses unmodified armor damage")
