extends RefCounted
## MMORPG-style focus fire without client-selected targets, PvP amplification or
## untrusted party state. All tests use server-owned enemies and positions.

const PartyFocus = preload("res://scripts/shared/party_focus.gd")
const Party = preload("res://scripts/shared/party.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "bounded infected focus geometry and damage"
	t.check(PartyFocus.in_range(Vector3.ZERO, Vector3(24.0, 0.0, 0.0)),
		"24 metre range includes its boundary")
	t.check(not PartyFocus.in_range(Vector3.ZERO, Vector3(24.1, 0.0, 0.0)),
		"out of range cannot get a focus bonus")
	t.check(not PartyFocus.in_range(Vector3.ZERO, Vector3(0.0, 4.1, 0.0)),
		"vertical floor separation is limited")
	t.check(not PartyFocus.in_range(Vector3(INF, 0, 0), Vector3.ZERO),
		"non-finite coordinates are invalid")
	t.near(PartyFocus.damage(10.0, true), 10.8, 0.001,
		"authorized infected attacks receive an 8 percent bonus")
	t.near(PartyFocus.damage(10.0, false), 10.0, 0.001,
		"unmarked targets receive exactly their original damage")
	t.near(PartyFocus.damage(0.0, true), 0.0, 0.001,
		"invalid zero damage never becomes an attack")

	t.current = "leadership, privacy, expiry and membership changes"
	var parties := Party.new()
	t.eq(parties.start_focus(50, 777, 0.0).get("reason", ""), "not_in_party",
		"solo players cannot create party buffs")
	t.check(parties.invite(1, 2, 0.0).get("ok", false), "leader creates party")
	t.check(parties.accept(2, 0.1).get("ok", false), "teammate joins")
	t.eq(parties.start_focus(2, 777, 1.0).get("reason", ""), "leader_only",
		"nonleader cannot mark targets")
	t.eq(parties.start_focus(1, 0, 1.0).get("reason", ""), "invalid_target",
		"invalid target does not use cooldown")
	t.check(parties.start_focus(1, 777, 1.0).get("ok", false),
		"leader can focus a validated infected")
	t.eq(parties.start_focus(1, 888, 1.5).get("reason", ""), "already_active",
		"active target cannot be replaced immediately")
	t.check(parties.has_focus(1, 777, 2.0) and parties.has_focus(2, 777, 2.0),
		"all actual members share the same target")
	t.check(not parties.has_focus(2, 888, 2.0),
		"mark does not grant damage on a different infected")
	t.check(not parties.has_focus(30, 777, 2.0),
		"outsider cannot share another party's bonus")
	t.eq(parties.state_for(30, 2.0).get("focus", {}), {},
		"focus marker is not exposed in unrelated snapshots")
	t.eq(int(parties.state_for(2, 2.0)["focus"]["target"]), 777,
		"member sees their target for tactical coordination")
	t.check(not parties.has_focus(2, 777, 20.0), "mark expires on clock boundary")
	t.eq(parties.start_focus(1, 888, 20.0).get("reason", ""), "cooldown",
		"leader cannot spam focus as soon as it expires")
	parties.expire(20.0)
	t.eq(parties.state_for(1, 20.0)["focus"], {}, "expired state is cleared")
	t.check(parties.start_focus(1, 888, 29.0).get("ok", false),
		"leader can mark a new infected after cooldown")
	parties.clear_focus_target(777)
	t.check(parties.has_focus(2, 888, 30.0),
		"killing a different target does not clear this focus")
	parties.clear_focus_target(888)
	t.eq(parties.state_for(2, 30.0)["focus"], {},
		"dead marked infected is removed immediately")
	t.check(parties.start_focus(1, 999, 58.0).get("ok", false),
		"leader can mark again on subsequent cooldown")
	parties.cancel_focus_by(2)
	t.check(parties.has_focus(1, 999, 58.1),
		"a regular member's death cannot cancel the leader marker")
	parties.cancel_focus_by(1)
	t.eq(parties.state_for(2, 58.1)["focus"], {},
		"leader death cancels party focus")
	t.check(parties.start_focus(1, 999, 86.0).get("ok", false),
		"a fresh marker is possible after cooldown")
	t.check(parties.invite(1, 3, 87.0).get("ok", false), "party can invite new member")
	t.check(parties.accept(3, 87.1).get("ok", false), "new member joins")
	t.eq(parties.state_for(1, 87.1)["focus"], {},
		"joining a team cancels an old mark and its permissions")
	t.check(parties.start_focus(1, 999, 114.0).get("ok", false),
		"leader may focus after a new cooldown")
	t.check(parties.kick(1, 3).get("ok", false), "leader can remove member")
	t.eq(parties.state_for(2, 114.1)["focus"], {},
		"removing a member invalidates old shared tactics")
	t.check(parties.start_focus(1, 1000, 142.0).get("ok", false),
		"mark remains usable while there are two teammates")
	t.check(parties.leave(2).get("ok", false), "final teammate leaves")
	t.eq(parties.state_for(1, 142.1)["focus"], {},
		"disbanded party cannot keep its buff")

	t.current = "server-owned nearest infected selection and actual damage"
	var world := WorldGen.new(819)
	var sim := GameServer.new(world, 819)
	var leader = sim.add_player(101, "Scout")
	var ally = sim.add_player(102, "Archer")
	var stranger = sim.add_player(103, "Wanderer")
	# Fix a common ground plane so procedural height differences cannot
	# accidentally disqualify an otherwise nearby infected in this unit test.
	leader.position = Vector3(210.0, 5.0, 210.0)
	ally.position = Vector3(211.0, 5.0, 210.0)
	stranger.position = Vector3(212.0, 5.0, 210.0)
	sim.zombies.clear() # Deterministic enemy set, no procedural encounters.
	t.check(sim.cmd_party_invite(101, 102).get("ok", false), "nearby invite authorized")
	t.check(sim.cmd_party_accept(102).get("ok", false), "teammate joined")
	t.eq(sim.cmd_party_focus(102).get("reason", ""), "leader_only",
		"nonleader cannot mark from a forged client")
	t.eq(sim.cmd_party_focus(103).get("reason", ""), "not_in_party",
		"outsider is excluded by the server")
	t.eq(sim.cmd_party_focus(101).get("reason", ""), "no_infected_nearby",
		"no target means no focus or cooldown")
	var near_enemy = Zombie.new(sim.new_id(), "walker", Vector3(214.0, 5.0, 210.0))
	var far_enemy = Zombie.new(sim.new_id(), "walker", Vector3(230.0, 5.0, 210.0))
	var dead_enemy = Zombie.new(sim.new_id(), "walker", Vector3(211.0, 5.0, 210.0))
	dead_enemy.take_damage(1000.0, 101)
	sim.zombies[near_enemy.id] = near_enemy
	sim.zombies[far_enemy.id] = far_enemy
	sim.zombies[dead_enemy.id] = dead_enemy
	var marked: Dictionary = sim.cmd_party_focus(101)
	t.check(marked.get("ok", false), "leader focuses the nearest live infected")
	t.eq(int(marked.get("target", -1)), near_enemy.id,
		"dead or more distant zombies are not selected")
	t.eq(sim.cmd_party_focus(101).get("reason", ""), "already_active",
		"repeat RPC cannot reset the damage-buff timer")
	t.eq(sim.snapshot_for(102)["you"]["party"]["focus"]["target"], near_enemy.id,
		"teammate sees marked enemy in private snapshot")
	t.eq(sim.snapshot_for(103)["you"]["party"]["focus"], {},
		"stranger receives no focus intelligence")
	var old_health: float = near_enemy.health
	sim._damage_target(ally, {"kind": "zombie", "id": near_enemy.id}, 10.0)
	t.near(old_health - near_enemy.health, 10.8, 0.001,
		"real teammate PvE hit receives bounded focus bonus")
	old_health = near_enemy.health
	sim._damage_target(stranger, {"kind": "zombie", "id": near_enemy.id}, 5.0)
	t.near(old_health - near_enemy.health, 5.0, 0.001,
		"nonmember hitting marked target has no damage bonus")
	old_health = far_enemy.health
	sim._damage_target(ally, {"kind": "zombie", "id": far_enemy.id}, 5.0)
	t.near(old_health - far_enemy.health, 5.0, 0.001,
		"teammate cannot amplify damage to an unmarked enemy")
	sim.time += PartyFocus.DURATION + 0.1
	old_health = near_enemy.health
	sim._damage_target(ally, {"kind": "zombie", "id": near_enemy.id}, 5.0)
	t.near(old_health - near_enemy.health, 5.0, 0.001,
		"expired focus grants no further damage")
	sim.time = PartyFocus.COOLDOWN + 1.0
	t.check(sim.cmd_party_focus(101).get("ok", false),
		"leader can focus the next encounter after cooldown")
	sim._damage_target(ally, {"kind": "zombie", "id": near_enemy.id}, 100.0)
	t.eq(sim.snapshot_for(102)["you"]["party"]["focus"], {},
		"focus kill clears it from the group snapshot")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_party_focus"), "client RPC exists and uses the authenticated sender")
	net.free()
