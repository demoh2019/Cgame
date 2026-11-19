extends RefCounted
## Lineage-style team play without client-authored membership or free XP.

const Party = preload("res://scripts/shared/party.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "party member limits, leadership and invitation lifecycle"
	var groups := Party.new()
	t.eq(groups.invite(1, 1, 0.0)["reason"], "invalid_target", "cannot self-invite")
	t.check(groups.invite(1, 2, 0.0)["ok"], "leader creates a party through first invite")
	t.eq(groups.invite(1, 2, 0.0)["reason"], "already_invited",
		"cannot replace a pending valid invitation")
	t.eq(groups.state_for(2)["invite_from"], 1, "recipient sees a private invite")
	t.check(groups.accept(2, 1.0)["ok"], "member accepts invitation")
	t.eq(groups.members_of(1).size(), 2, "party contains exactly two members")
	t.eq(groups.accept(2, 2.0)["reason"], "no_invite", "replayed acceptance grants no duplicate")
	t.eq(groups.invite(2, 3, 2.0)["reason"], "leader_only", "members cannot invite as leader")
	for target in [3, 4, 5]:
		t.check(groups.invite(1, target, 2.0)["ok"], "leader invites a member")
		t.check(groups.accept(target, 3.0)["ok"], "member joins once")
	t.eq(groups.members_of(1).size(), Party.MAX_MEMBERS, "group reaches capacity 5")
	t.eq(groups.invite(1, 6, 3.0)["reason"], "party_full", "sixth member rejected")
	t.eq(groups.kick(2, 5)["reason"], "leader_only", "regular member cannot kick")
	t.check(groups.kick(1, 5)["ok"], "leader can remove an actual member")
	t.eq(groups.group_of(5), 0, "kicked player has no remaining membership")
	t.check(groups.invite(1, 6, 4.0)["ok"], "one vacant slot can be invited")
	t.eq(groups.accept(6, 35.0)["reason"], "expired", "expired invite is rejected")
	t.eq(groups.group_of(6), 0, "expired invite never changed membership")
	t.check(groups.invite(1, 6, 36.0)["ok"], "new invitation may be issued")
	t.check(groups.decline(6)["ok"], "recipient may decline")
	t.eq(groups.accept(6, 37.0)["reason"], "no_invite", "declined invitation cannot be replayed")
	t.check(groups.leave(1)["ok"], "leader may leave")
	t.eq(groups.state_for(2)["leader"], 2, "leadership transfers to first survivor")
	t.check(groups.invite(2, 6, 40.0)["ok"], "new leader may invite")
	groups.disconnect(6)
	t.eq(groups.accept(6, 41.0)["reason"], "no_invite", "disconnect removes pending invite")
	t.eq(groups.group_of(1), 0, "leader is no longer in the team")
	groups.disconnect(2)
	groups.disconnect(3)
	groups.disconnect(4)
	t.eq(groups.groups.size(), 0, "all groups cleaned on disconnect")
	t.eq(groups.group_by_peer.size(), 0, "no stale session member mapping")

	t.current = "server authority, proximity and private roster"
	var world := WorldGen.new(22)
	var server := GameServer.new(world, 22)
	var leader = server.add_player(101, "Leader")
	var ally = server.add_player(102, "Medic")
	var stranger = server.add_player(103, "Stranger")
	leader.position = _at(world, 250.0, 250.0)
	ally.position = _at(world, 250.0, 252.0)
	stranger.position = _at(world, 550.0, 550.0)
	t.eq(server.cmd_party_invite(101, 103)["reason"], "too_far",
		"remote players cannot be invited through forged peer IDs")
	t.check(server.cmd_party_invite(101, 102)["ok"], "nearby survivor invited")
	t.eq(server.snapshot_for(102)["you"]["party"]["invite_from"], 101,
		"only invitee has a party invite in private snapshot")
	t.eq(server.snapshot_for(103)["you"]["party"]["invite_from"], 0,
		"strangers cannot see another player's invite")
	ally.position = _at(world, 500.0, 500.0)
	t.eq(server.cmd_party_accept(102)["reason"], "too_far",
		"running away before acceptance denies remote joining")
	ally.position = _at(world, 250.0, 252.0)
	t.check(server.cmd_party_accept(102)["ok"], "joining in the required range succeeds")
	var snapshot: Dictionary = server.snapshot_for(101)
	t.eq(snapshot["you"]["party"]["roster"].size(), 2,
		"leader sees names and vital status of real party members")
	t.eq(server.snapshot_for(103)["you"]["party"]["id"], 0,
		"unrelated survivor sees no roster or party identity")

	t.current = "friendly fire is prevented in otherwise lethal PvP zones"
	leader.position = _at(world, 900.0, 900.0)
	ally.position = _at(world, 901.0, 900.0)
	var health_before: float = ally.survival.health
	server._damage_target(leader, {"kind": "player", "id": 102}, 40.0)
	t.eq(ally.survival.health, health_before,
		"server rejects damage to a party member even in a risk zone")

	t.current = "only real, recent combat contributors earn assist mastery"
	leader.inventory.add("club_1", 1)
	ally.inventory.add("club_1", 1)
	leader.inventory.equip("club_1")
	ally.inventory.equip("club_1")
	stranger.inventory.add("club_1", 1)
	stranger.inventory.equip("club_1")
	stranger.position = _at(world, 901.0, 901.0)
	var infected = Zombie.new(server.new_id(), "walker", _at(world, 902.0, 900.0))
	server.zombies[infected.id] = infected
	server._damage_target(ally, {"kind": "zombie", "id": infected.id}, 5.0)
	t.eq(ally.progression.combat_xp["melee"], 0, "hitting alone does not grant kill XP")
	server._damage_target(leader, {"kind": "zombie", "id": infected.id}, 100.0)
	t.eq(leader.progression.combat_xp["melee"], 5, "killer receives full zombie XP")
	t.eq(ally.progression.combat_xp["melee"], 2, "actual contributor receives bounded 50% assist")
	t.eq(stranger.progression.combat_xp["melee"], 0, "stranger receives zero XP")
	server._damage_target(leader, {"kind": "zombie", "id": infected.id}, 100.0)
	t.eq(ally.progression.combat_xp["melee"], 2, "dead zombie cannot grant replay XP")
	t.eq(ally.kills, 0, "assisting is not a credited personal kill")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "mastery", "peer": 102}, 102),
		"mastery XP is delivered to its legitimate recipient")
	t.check(not net._event_visible_to({"type": "mastery", "peer": 102}, 103),
		"private mastery results are not broadcast to strangers")
	net.free()

	t.current = "no AFK or stale damage shared XP"
	var idle = Zombie.new(server.new_id(), "walker", _at(world, 904.0, 900.0))
	server.zombies[idle.id] = idle
	server._damage_target(leader, {"kind": "zombie", "id": idle.id}, 100.0)
	t.eq(ally.progression.combat_xp["melee"], 2, "idle nearby party member gains no XP")
	var stale = Zombie.new(server.new_id(), "walker", _at(world, 905.0, 900.0))
	server.zombies[stale.id] = stale
	server._damage_target(ally, {"kind": "zombie", "id": stale.id}, 5.0)
	server.time += Party.ASSIST_WINDOW + 1.0
	server._damage_target(leader, {"kind": "zombie", "id": stale.id}, 100.0)
	t.eq(ally.progression.combat_xp["melee"], 2, "old damage outside assist window grants no XP")
	t.check(server.cmd_party_leave(102)["ok"], "leaving group is always available")
	t.eq(server.snapshot_for(102)["you"]["party"]["id"], 0,
		"member list clears in next snapshot")
	t.eq(server.snapshot_for(101)["you"]["party"]["id"], 0,
		"one-person remnants automatically disband")
