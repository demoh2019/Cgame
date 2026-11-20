extends RefCounted
## Confirmed guardian intercept -> PvE-only one-swing retaliation against the
## exact infected that landed the intercepted blow.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const GuardianRetribution = preload("res://scripts/shared/guardian_retribution.gd")
const GuardianIntercept = preload("res://scripts/shared/guardian_intercept.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "finite one-time melee counterstrike values"
	t.near(GuardianRetribution.amplify(20.0), 25.0, 0.001,
		"earned counterstrike grants +25% damage")
	t.near(GuardianRetribution.amplify(-2.0), 0.0, 0.001,
		"negative damage cannot cause healing")
	t.near(GuardianRetribution.amplify(NAN), 0.0, 0.001,
		"nonfinite damage is blocked")
	t.near(GuardianRetribution.COUNTER_SECONDS, 4.0, 0.001,
		"retaliation lasts at most four server seconds")
	t.near(GuardianRetribution.TAUNT_SECONDS, 1.5, 0.001,
		"rescued infected is challenged for only 1.5 seconds")

	t.current = "real intercepted zombie hit earns a private counterattack"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var guardian = sim.add_player(41, "Guardian")
	var ally = sim.add_player(42, "Healer")
	var stranger = sim.add_player(43, "Unrelated")
	guardian.position = _at(world, 310.0, 0.0)
	ally.position = _at(world, 313.0, 0.0)
	stranger.position = _at(world, 325.0, 0.0)
	t.check(sim.cmd_party_invite(41, 42).get("ok", false),
		"real group invite is sent")
	t.check(sim.cmd_party_accept(42).get("ok", false),
		"real group is joined")
	guardian.inventory.add("club_1", 1)
	t.check(guardian.inventory.equip("club_1"),
		"guardian actually owns and equips a melee weapon")
	var enemy := Zombie.new(sim.new_id(), "brute", _at(world, 312.0, 0.0))
	sim.zombies[enemy.id] = enemy
	enemy.target_id = ally.id
	enemy.state = Zombie.State.ATTACK
	enemy.think_timer = 1.0
	enemy.attack_timer = 0.0
	t.eq(guardian.guard_counter_target, -1, "no free counter before a rescue")
	t.check(not GuardianRetribution.arm(ally, enemy, sim.parties, world),
		"unequipped ally cannot self-create a guardian counter")
	t.check(sim.cmd_guardian_intercept(41, 42).get("ok", false),
		"party guardian arms a real protection link")
	var before_ally: float = ally.survival.health
	sim._tick_zombies(0.05)
	t.near(ally.survival.health, before_ally, 0.001,
		"one real infected strike was intercepted")
	var saved_events: Array = sim.events.filter(
		func(event): return event.get("type", "") == "guardian_intercept")
	t.eq(saved_events.size(), 1, "one genuine rescue generates one server event")
	if saved_events.size() == 1:
		t.check(bool(saved_events[0].get("counter_ready", false)),
			"guardian receives a counter prompt only when they survived the block")
	t.eq(guardian.guard_counter_target, enemy.id,
		"only actual enemy that struck is marked for retaliation")
	t.eq(guardian.guard_counter_weapon, "club_1",
		"server freezes real equipment used when saving the ally")
	t.eq(guardian.guard_counter_party, sim.parties.group_of(41),
		"one real party owns the earned counterattack")
	t.near(guardian.guard_counter_seconds, 4.0, 0.001,
		"successful intercept grants exact server-owned time window")
	t.eq(enemy.forced_target_id, guardian.id,
		"same infected now focuses the guardian, not the protected medic")
	t.eq(enemy.target_id, guardian.id,
		"enemy immediately changes target to the rescuer")
	t.near(enemy.forced_target_seconds, 1.5, 0.001,
		"the challenge's expiry is bounded")
	t.eq(int(sim.snapshot_for(41)["you"]["guardian_counter_target"]), enemy.id,
		"guardian sees own exact retaliatory target in a private snapshot")
	t.near(float(sim.snapshot_for(41)["you"]["guardian_counter_seconds"]),
		GuardianRetribution.COUNTER_SECONDS, 0.001,
		"HUD countdown comes from the authoritative server")
	t.eq(int(sim.snapshot_for(43)["you"]["guardian_counter_target"]), -1,
		"stranger cannot observe a different party's counter target")
	t.eq(int(sim.snapshot_for(42)["you"]["guardian_counter_target"]), -1,
		"even the protected ally does not receive another player's mark")

	t.current = "first genuine basic melee hit consumes the earned retaliation"
	# Move just the infected closer; valid server hit geometry remains in force.
	enemy.position = _at(world, 310.9, 0.0)
	enemy.think_timer = 1.0
	var before_enemy: float = enemy.health
	var first: Dictionary = sim.cmd_attack(41, 1.0, 0.0)
	t.check(first.get("ok", false) and first.get("hit", false),
		"first normal attack is a confirmed melee collision")
	t.eq(first.get("target", ""), "zombie", "counter attacks infected, not players")
	t.check(bool(first.get("guardian_retribution", false)),
		"the first matching infected hit receives a one-use bonus")
	t.check(enemy.health < before_enemy, "server applies real infected damage")
	t.eq(guardian.guard_counter_target, -1, "mark consumed after the first swing")
	t.near(guardian.guard_counter_seconds, 0.0, 0.001,
		"successful counter cannot be applied a second time")
	t.eq(sim.events.filter(func(event): return event.get("type", "") == "guardian_retribution").size(),
		1, "one successful counter emits exactly one private notification")
	var before_second: float = enemy.health
	guardian.attack_timer = 0.0
	var second: Dictionary = sim.cmd_attack(41, 1.0, 0.0)
	t.check(second.get("ok", false) and second.get("hit", false),
		"normal consecutive attack still works after the link is spent")
	t.check(not bool(second.get("guardian_retribution", false)),
		"repeated attack has no bonus without a second rescue")
	t.check(enemy.health < before_second, "unboosted attack still deals normal damage")
	t.eq(sim.events.filter(func(event): return event.get("type", "") == "guardian_retribution").size(),
		1, "repeated attacks cannot farm reactive announcements")

	t.current = "miss, wrong enemy and invalid gear spend no PvP bonus"
	t.check(GuardianRetribution.arm(guardian, enemy, sim.parties, world),
		"new earned state may only be created by the trusted server API")
	guardian.attack_timer = 0.0
	var missed: Dictionary = sim.cmd_attack(41, -1.0, 0.0)
	t.check(missed.get("ok", false) and not missed.get("hit", true),
		"turning away produces a real melee miss")
	t.eq(guardian.guard_counter_target, -1, "first miss spends the opportunity")
	var unrelated := Zombie.new(sim.new_id(), "walker", _at(world, 311.0, 0.0))
	sim.zombies[unrelated.id] = unrelated
	t.check(GuardianRetribution.arm(guardian, enemy, sim.parties, world),
		"fresh state still points to the original attacker")
	t.check(not GuardianRetribution.consume(guardian, unrelated, sim.parties, world),
		"wrong infected can never steal the +25% damage bonus")
	t.eq(guardian.guard_counter_target, -1, "wrong target still consumes a melee attempt")
	t.check(GuardianRetribution.arm(guardian, enemy, sim.parties, world),
		"rearm for a gear validation case")
	guardian.inventory.remove("club_1", 1)
	t.check(not GuardianRetribution.consume(guardian, enemy, sim.parties, world),
		"switching or losing physical melee gear prevents the counter")
	guardian.inventory.add("club_1", 1)
	guardian.inventory.equip("club_1")
	t.check(GuardianRetribution.arm(guardian, enemy, sim.parties, world),
		"guardian may rearm only while still actually equipped")
	t.check(sim.cmd_party_leave(42).get("ok", false), "ally legitimately leaves group")
	t.check(not GuardianRetribution.consume(guardian, enemy, sim.parties, world),
		"party disbanding invalidates the stored combat opportunity")
	t.eq(guardian.guard_counter_target, -1, "disbanded team cannot retain a marked victim")

	t.current = "time and death clean session-only reactive state"
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "party reforms")
	t.check(sim.cmd_party_accept(42).get("ok", false), "ally rejoins")
	t.check(GuardianRetribution.arm(guardian, enemy, sim.parties, world),
		"third legitimate counter window can expire")
	sim._tick_players(GuardianRetribution.COUNTER_SECONDS + 0.1)
	t.near(guardian.guard_counter_seconds, 0.0, 0.001, "server tick expires counter window")
	t.eq(guardian.guard_counter_target, -1, "expiry removes the exact infected target")
	t.check(GuardianRetribution.arm(guardian, enemy, sim.parties, world),
		"rearm for death cleanup")
	guardian.survival.hurt(999.0)
	sim._on_player_death(guardian, -enemy.id)
	t.eq(guardian.guard_counter_target, -1, "death removes earned counterstrike")
	t.near(guardian.guard_counter_seconds, 0.0, 0.001, "dead guardian retains no buff")
	sim._spawn_player(guardian)
	t.eq(guardian.guard_counter_target, -1, "respawn cannot restore combat protection")

	t.current = "counterstrike events and enemy target never leak through the network"
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var public_event := {"type": "guardian_retribution", "peer": 41, "zombie": enemy.id}
	t.check(net._event_visible_to(public_event, 41),
		"earned guardian sees their own counterstrike message")
	t.check(not net._event_visible_to(public_event, 42),
		"even a teammate cannot read the guardian's private target ID")
	t.check(not net._event_visible_to(public_event, 43),
		"strangers cannot scout private combat targets from an event")
	net.free()
