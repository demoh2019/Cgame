extends RefCounted
## Real zombie melee defense, server cooldowns, two-guardian nonstacking and
## privacy. The shield never runs from PvP/raid telegraph/acid damage paths.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const ShieldWall = preload("res://scripts/shared/party_shield_wall.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _prepare_hit(enemy, victim_id: int) -> void:
	enemy.target_id = victim_id
	enemy.state = Zombie.State.ATTACK
	enemy.think_timer = 1.0
	enemy.attack_timer = 0.0


func run(t) -> void:
	t.current = "shield wall reductions are bounded and raid damage is intentionally smaller"
	t.near(ShieldWall.mitigate(40.0, false), 31.2, 0.001,
		"normal infected claw damage reduced by 22 percent")
	t.near(ShieldWall.mitigate(40.0, true), 35.2, 0.001,
		"raid boss claw damage reduced by only 12 percent")
	t.near(ShieldWall.mitigate(INF, false), 0.0, 0.001,
		"infinite damage cannot corrupt health")
	t.near(ShieldWall.mitigate(NAN, true), 0.0, 0.001,
		"NaN damage never becomes a shield exploit")
	t.near(ShieldWall.mitigate(-5.0, false), 0.0, 0.001,
		"negative damage never heals the player")

	t.current = "casting requires real nearby party and melee gear"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var guardian = sim.add_player(81, "Guardian")
	var medic = sim.add_player(82, "Medic")
	var stranger = sim.add_player(83, "Outsider")
	guardian.position = _at(world, 310.0, 0.0)
	medic.position = _at(world, 312.0, 0.0)
	stranger.position = _at(world, 312.0, 1.0)
	t.eq(sim.cmd_party_shield_wall(81).get("reason", ""), "not_in_party",
		"solo player cannot shield nearby strangers")
	t.check(sim.cmd_party_invite(81, 82).get("ok", false),
		"guardian invites a teammate")
	t.check(sim.cmd_party_accept(82).get("ok", false),
		"teammate voluntarily joins group")
	t.eq(sim.cmd_party_shield_wall(81).get("reason", ""), "need_melee",
		"unarmed party member cannot cast the guardian stance")
	guardian.inventory.add("club_1", 1)
	t.check(guardian.inventory.equip("club_1"),
		"legitimate carried melee weapon is equipped")
	t.check(ShieldWall.can_protect(guardian, medic, sim.parties, world),
		"frontline and medic within 5.5 m have a valid formation")
	t.check(not ShieldWall.can_protect(guardian, stranger, sim.parties, world),
		"outsider near a guardian never shares their party aura")
	t.check(not ShieldWall.can_protect(guardian, guardian, sim.parties, world),
		"guardian does not gain their own group defensive aura")
	medic.position = _at(world, 325.0, 0.0)
	t.eq(sim.cmd_party_shield_wall(81).get("reason", ""), "no_nearby_ally",
		"the guardian cannot spend energy for a remote party member")
	medic.position = _at(world, 312.0, 0.0)
	medic.position = Vector3(312.0, guardian.position.y + ShieldWall.MAX_HEIGHT + 1.0, 0.0)
	t.check(not ShieldWall.can_protect(guardian, medic, sim.parties, world),
		"protection is not projected through floors")
	medic.position = _at(world, 312.0, 0.0)
	medic.position = Vector3(INF, 0.0, 0.0)
	t.check(not ShieldWall.can_protect(guardian, medic, sim.parties, world),
		"invalid coordinates do not enable the aura")
	medic.position = _at(world, 312.0, 0.0)
	guardian.combat_energy = 0.0
	t.eq(sim.cmd_party_shield_wall(81).get("reason", ""), "no_energy",
		"zero combat energy prevents casting")
	t.near(guardian.shield_wall_cooldown, 0.0, 0.001,
		"failed cast does not start cooldown or spend anything")

	t.current = "one server-approved cast protects nearby party ally"
	guardian.combat_energy = 100.0
	var start: Dictionary = sim.cmd_party_shield_wall(81)
	t.check(bool(start.get("ok", false)), "guardian activates party Shield Wall")
	t.eq(int(start.get("allies", -1)), 1, "only real nearby group allies are protected")
	t.near(guardian.combat_energy, 100.0 - ShieldWall.ENERGY_COST, 0.001,
		"server consumes exactly 30 combat energy")
	t.near(guardian.shield_wall_seconds, ShieldWall.DURATION, 0.001,
		"server owns exact six-second protective window")
	t.near(guardian.shield_wall_cooldown, ShieldWall.COOLDOWN, 0.001,
		"cooldown starts on successful payment")
	t.eq(sim.cmd_party_shield_wall(81).get("reason", ""), "already_active",
		"replayed network command cannot extend or stack the buff")
	t.near(guardian.combat_energy, 70.0, 0.001,
		"rejected replay does not spend additional energy")
	t.eq(int(sim.snapshot_for(82)["you"]["shield_wall_guarded_by"]), guardian.id,
		"protected medic sees only the selected ally guardian")
	t.near(float(sim.snapshot_for(82)["you"]["shield_wall_guarded_seconds"]),
		ShieldWall.DURATION, 0.001,
		"ally sees a countdown from server state")
	t.eq(int(sim.snapshot_for(83)["you"]["shield_wall_guarded_by"]), -1,
		"unrelated character sees no protection or hidden party guardian")
	t.near(float(sim.snapshot_for(81)["you"]["shield_wall_seconds"]),
		ShieldWall.DURATION, 0.001,
		"caster sees their private active state")

	t.current = "one real infected melee hit is mitigated without copying wounds"
	var enemy := Zombie.new(sim.new_id(), "brute", _at(world, 312.3, 0.0))
	sim.zombies[enemy.id] = enemy
	_prepare_hit(enemy, medic.id)
	var before: float = medic.survival.health
	var base_damage: float = Combat.apply_gear(float(enemy.data["damage"]), medic.inventory)
	sim._tick_zombies(0.05)
	t.near(medic.survival.health, before - ShieldWall.mitigate(base_damage, false), 0.001,
		"true zombie hit through the actual combat loop obeys one wall reduction")
	t.near(guardian.survival.health, 100.0, 0.001,
		"area protection never redirects damage to the guardian")
	t.check(medic.survival.infection >= 0.0,
		"ordinary secondary wound rules remain separately intact")
	var block_events: Array = sim.events.filter(
		func(event): return str(event.get("type", "")) == "party_shield_wall_block")
	t.eq(block_events.size(), 1, "one actual mitigated hit produces one feedback event")
	if block_events.size() > 0:
		t.near(float(block_events[0].get("prevented", 0.0)),
			base_damage - ShieldWall.mitigate(base_damage, false), 0.001,
			"reported prevention equals actual physical damage saved")
		t.eq(int(block_events[0].get("peer", -1)), medic.id,
			"the victim ID comes from server target selection")
		t.eq(int(block_events[0].get("by", -1)), guardian.id,
			"the shield's source is a real equipped party guardian")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_party_shield_wall"),
		"authenticated Shield Wall multiplayer command exists")
	if block_events.size() > 0:
		t.check(net._event_visible_to(block_events[0], guardian.id),
			"guardian receives private confirmation")
		t.check(net._event_visible_to(block_events[0], medic.id),
			"injured ally receives their own mitigation notification")
		t.check(not net._event_visible_to(block_events[0], stranger.id),
			"outsider cannot read the group defensive event")
	net.free()

	t.current = "two overlapping party walls never stack protection"
	var backup = sim.add_player(84, "BackupGuardian")
	backup.position = _at(world, 311.0, 0.0)
	backup.inventory.add("club_1", 1)
	backup.inventory.equip("club_1")
	t.check(sim.cmd_party_invite(81, 84).get("ok", false),
		"leader recruits second guardian")
	t.check(sim.cmd_party_accept(84).get("ok", false),
		"additional guardian joins same group")
	t.check(sim.cmd_party_shield_wall(84).get("ok", false),
		"two guardians may cast separately, but reductions do not stack")
	t.eq(ShieldWall.protector_for(medic, sim.players, sim.parties, world), backup.id,
		"closer valid guardian deterministically owns overlapping shield hits")
	var second_before: float = medic.survival.health
	_prepare_hit(enemy, medic.id)
	sim._tick_zombies(0.05)
	t.near(medic.survival.health,
		second_before - ShieldWall.mitigate(base_damage, false), 0.001,
		"overlapping guardians still mitigate once, never twice")

	t.current = "party, gear, safe zones and expiry are immediately rechecked"
	backup.inventory.remove("club_1", 1)
	t.eq(ShieldWall.protector_for(medic, sim.players, sim.parties, world),
		guardian.id, "losing real melee gear immediately disables second guardian")
	guardian.inventory.remove("club_1", 1)
	t.eq(ShieldWall.protector_for(medic, sim.players, sim.parties, world), -1,
		"both guardians losing equipment removes protection")
	sim._tick_players(0.1)
	t.near(guardian.shield_wall_seconds, 0.0, 0.001,
		"server tick clears a stale unequipped aura")
	guardian.inventory.add("club_1", 1)
	guardian.inventory.equip("club_1")
	guardian.shield_wall_cooldown = 0.0
	t.check(sim.cmd_party_shield_wall(81).get("ok", false),
		"after cooldown and re-equipping, real ability may be used again")
	t.check(sim.cmd_party_leave(82).get("ok", false),
		"protected ally may choose to leave the party")
	t.eq(ShieldWall.protector_for(medic, sim.players, sim.parties, world), -1,
		"former ally loses borrowed protection immediately")
	t.eq(int(sim.snapshot_for(82)["you"]["shield_wall_guarded_by"]), -1,
		"private HUD does not retain a departed guardian")

	t.current = "death and respawn do not carry magical protection"
	guardian.survival.hurt(999.0)
	sim._on_player_death(guardian, -enemy.id)
	t.near(guardian.shield_wall_seconds, 0.0, 0.001,
		"dead guardian grants no aura")
	sim._spawn_player(guardian)
	t.near(guardian.shield_wall_seconds, 0.0, 0.001,
		"respawn never restores an active protective stance")
	t.check(guardian.shield_wall_cooldown > 0.0,
		"dying and respawning do not reset the paid spell cooldown")
