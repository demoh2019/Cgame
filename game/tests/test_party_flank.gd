extends RefCounted
## Formations, server hit authority, actual team target and PvE-only bonuses.
## Crouched ambush only applies to unaware infected, unlike this combat flank.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const PartyFlank = preload("res://scripts/shared/party_flank.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _engaged(sim, world, tank_id: int, x: float = 310.0, z: float = 0.0):
	var infected := Zombie.new(sim.new_id(), "brute", _at(world, x, z))
	infected.state = Zombie.State.CHASE
	infected.target_id = tank_id
	sim.zombies[infected.id] = infected
	return infected


func run(t) -> void:
	t.current = "cooperative melee bonus is finite and boss-safe"
	t.near(PartyFlank.damage(20.0, false), 23.6, 0.001,
		"ordinary infected flank yields 18 percent damage")
	t.near(PartyFlank.damage(20.0, true), 22.0, 0.001,
		"raid boss flank yields a smaller 10 percent bonus")
	t.near(PartyFlank.damage(INF, false), 0.0, 0.001,
		"nonfinite damage cannot create unsafe health changes")
	t.near(PartyFlank.damage(-10.0, true), 0.0, 0.001,
		"negative flanking damage never becomes healing")

	t.current = "a melee party behind an actively engaged infected"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var tank = sim.add_player(41, "Guardian")
	var flanker = sim.add_player(42, "Blademaster")
	var stranger = sim.add_player(43, "Bystander")
	tank.position = _at(world, 311.5, 0.0)
	flanker.position = _at(world, 308.5, 0.0)
	stranger.position = _at(world, 308.0, 1.0)
	var infected = _engaged(sim, world, tank.id)
	flanker.inventory.add("club_1", 1)
	t.check(flanker.inventory.equip("club_1"), "real owned melee weapon is equipped")
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"two unrelated survivors cannot manufacture coordinated damage")
	t.check(sim.cmd_party_invite(41, 42).get("ok", false),
		"tank invites teammate")
	t.check(sim.cmd_party_accept(42).get("ok", false),
		"teammate joins real party")
	t.check(PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"rear attacker qualifies only while ally holds the actual target")
	t.check(not PartyFlank.qualifies(tank, infected, sim.players, sim.parties, world),
		"current boss or infected target cannot flank their own enemy")
	t.check(not PartyFlank.qualifies(stranger, infected, sim.players, sim.parties, world),
		"stranger without party entitlement cannot join the bonus")
	t.check(not sim.snapshot_for(stranger.id)["you"].get("party_flank_hint", {}).has("zombie"),
		"stranger's private snapshot reveals no party flank state")
	t.eq(int(sim.snapshot_for(flanker.id)["you"]["party_flank_hint"].get("zombie", -1)),
		infected.id, "the flanker receives a target-specific private positioning hint")
	t.eq(int(sim.snapshot_for(flanker.id)["you"]["party_flank_hint"].get("bonus", 0)), 18,
		"ordinary infected hint accurately shows the 18 percent bonus")
	t.check(sim.snapshot_for(tank.id)["you"]["party_flank_hint"].is_empty(),
		"tank sees no false hint when facing the same enemy")
	var own_position: Vector3 = flanker.position
	flanker.position = _at(world, 311.0, 1.0)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"attacking from same side does not count as flanking")
	flanker.position = _at(world, 299.0, 0.0)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"an attack from far behind is not within melee flank reach")
	flanker.position = Vector3(308.5, infected.position.y + PartyFlank.MAX_HEIGHT + 1.0, 0.0)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"cross-floor attackers cannot qualify")
	flanker.position = Vector3(INF, 0.0, 0.0)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"invalid spatial coordinates cannot claim combat synergy")
	flanker.position = own_position
	var original_enemy_position: Vector3 = infected.position
	infected.position = Vector3(-1.0e30, infected.position.y, 0.0)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"extreme finite infected coordinates cannot grant a melee flank bonus")
	infected.position = original_enemy_position
	tank.position = _at(world, 325.0, 0.0)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"target ally must be close to the actual infected")
	tank.position = _at(world, 311.5, 0.0)
	infected.state = Zombie.State.IDLE
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"idle enemies with stale target IDs cannot grant group damage")
	infected.state = Zombie.State.CHASE
	infected.target_id = flanker.id
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"threat switch to attacker immediately cancels positional advantage")
	t.check(sim.snapshot_for(flanker.id)["you"]["party_flank_hint"].is_empty(),
		"HUD prompt clears when the infected turns on its flanker")
	infected.target_id = tank.id
	flanker.mounted = true
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"mounted survivors do not receive melee flanking")
	flanker.mounted = false
	flanker.inventory.remove("club_1", 1)
	t.check(not PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"ghost equipped items cannot create the damage bonus")
	flanker.inventory.add("club_1", 1)
	flanker.inventory.equip("club_1")
	t.check(PartyFlank.qualifies(flanker, infected, sim.players, sim.parties, world),
		"valid formation can resume after re-equipping a real weapon")

	t.current = "equal confirmed server damage differs only by the flank bonus"
	# Test the same GameServer damage pipeline with the same attacker,
	# weapon and target type. The basic-melee flag is internal only.
	var ordinary = _engaged(sim, world, tank.id, 310.0, 0.15)
	var enhanced = _engaged(sim, world, tank.id, 310.0, 0.20)
	var unboosted_health: float = ordinary.health
	var boosted_health: float = enhanced.health
	sim._damage_target(flanker, {"kind": "zombie", "id": ordinary.id}, 10.0, "melee")
	sim._damage_target(flanker, {"kind": "zombie", "id": enhanced.id}, 10.0, "melee", true)
	var base_loss: float = unboosted_health - ordinary.health
	var boosted_loss: float = boosted_health - enhanced.health
	t.check(base_loss > 0.0, "normal authoritative damage landed in control case")
	t.near(boosted_loss / maxf(0.001, base_loss), 1.18, 0.02,
		"an identical server melee damage path grants exactly 18 percent when flanking")
	# The controlled hits are synthetic and must not obstruct the later
	# fully authentic cmd_attack collision test.
	sim.zombies.erase(ordinary.id)
	sim.zombies.erase(enhanced.id)
	sim.events.clear()

	t.current = "only normal authoritative melee hit receives extra damage"
	var initial_hp: float = infected.health
	var strike: Dictionary = sim.cmd_attack(flanker.id, 1.0, 0.0)
	t.check(bool(strike.get("ok", false)) and bool(strike.get("hit", false)),
		"actual swing collides with the server's nearest infected")
	t.eq(str(strike.get("target", "")), "zombie",
		"authoritative combat chose a zombie, not a party member")
	t.check(bool(strike.get("party_flank", false)),
		"normal melee attack acknowledges a real coordinated flank")
	t.check(infected.health < initial_hp,
		"server applied ordinary damage plus the group position bonus")
	var flank_events: Array = sim.events.filter(
		func(e): return str(e.get("type", "")) == "party_flank")
	t.eq(flank_events.size(), 1, "one confirmed melee hit produces one private flank event")
	if flank_events.size() > 0:
		t.eq(int(flank_events[0].get("peer", -1)), flanker.id,
			"server attributes the bonus only to the actual swinging player")
		t.eq(int(flank_events[0].get("zombie", -1)), infected.id,
			"event references only the collided infected entity")
		t.eq(int(flank_events[0].get("bonus", -1)), 18,
			"ordinary infected event describes the 18 percent buff")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	if flank_events.size() > 0:
		t.check(net._event_visible_to(flank_events[0], flanker.id),
			"the flanker receives private feedback from the authenticated server")
		t.check(not net._event_visible_to(flank_events[0], tank.id),
			"another party member does not receive this attacker's private result")
		t.check(not net._event_visible_to(flank_events[0], stranger.id),
			"unrelated client cannot inspect positional attack events")
	net.free()

	t.current = "skills, ranged damage and generic damage calls never gain basic flank buff"
	var before_events: int = sim.events.filter(
		func(e): return str(e.get("type", "")) == "party_flank").size()
	var previous_hp: float = infected.health
	sim._damage_target(flanker, {"kind": "zombie", "id": infected.id}, 3.0, "melee")
	t.near(previous_hp - infected.health, Combat.against_infected(
		3.0 * (1.0 + flanker.skills.bonus("zombie_damage")),
		"club_1", true), 0.8,
		"generic melee damage path does not falsely grant formation bonuses")
	sim._damage_target(flanker, {"kind": "zombie", "id": infected.id}, 3.0, "ranged", true)
	t.eq(sim.events.filter(func(e): return str(e.get("type", "")) == "party_flank").size(),
		before_events, "ranged and skill-like damage never triggers a basic melee flank")

	t.current = "boss flank remains useful but yields smaller gains"
	var boss := Zombie.new(sim.new_id(), "brute", _at(world, 310.0, 0.0))
	RaidEncounter.empower(boss)
	boss.target_id = tank.id
	boss.state = Zombie.State.ATTACK
	sim.zombies[boss.id] = boss
	t.check(PartyFlank.qualifies(flanker, boss, sim.players, sim.parties, world),
		"engaged raid boss supports correct positioning")
	t.near(PartyFlank.damage(20.0, boss.raid_boss), 22.0, 0.001,
		"boss bonus is deliberately smaller than ordinary infected")

	t.current = "death and party change immediately invalidate the formation"
	t.check(sim.cmd_party_leave(42).get("ok", false),
		"flanker legitimately leaves the party")
	t.check(not PartyFlank.qualifies(flanker, boss, sim.players, sim.parties, world),
		"former party members immediately lose their tactical bonus")
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "party can form again")
	t.check(sim.cmd_party_accept(42).get("ok", false), "flanker rejoins")
	tank.survival.hurt(999.0)
	t.check(not PartyFlank.qualifies(flanker, boss, sim.players, sim.parties, world),
		"dying frontline cancels the positional opportunity")
	t.check(sim.snapshot_for(flanker.id)["you"]["party_flank_hint"].is_empty(),
		"dead tank cannot leave a stale glowing attack prompt")
