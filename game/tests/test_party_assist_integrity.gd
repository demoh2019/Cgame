extends RefCounted
## Regressions for retroactive group XP exploits.
## Hits are recorded by the real authoritative GameServer, never by clients.

const Party = preload("res://scripts/shared/party.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _walker(server, world):
	var entity := Zombie.new(server.new_id(), "walker", _at(world, 701.0, 200.0))
	server.zombies[entity.id] = entity
	return entity


func run(t) -> void:
	var world := WorldGen.new(250)
	var server := GameServer.new(world, 250)
	var leader = server.add_player(101, "Leader")
	var recruit = server.add_player(102, "Recruit")
	leader.position = _at(world, 700.0, 200.0)
	recruit.position = _at(world, 703.0, 200.0)
	for player in [leader, recruit]:
		player.inventory.add("club_1", 1)
		t.check(player.inventory.equip("club_1"), "survivor equips an owned weapon")

	t.current = "pre-invite contribution cannot earn retroactive mastery"
	var before_join = _walker(server, world)
	server._damage_target(recruit, {"kind": "zombie", "id": before_join.id}, 1.0)
	t.eq(int(before_join.contributors[102].get("group", -1)), 0,
			"ungrouped hit is explicitly signed as group zero")
	t.check(bool(server.cmd_party_invite(101, 102).get("ok", false)),
			"leader invites the recent contributor")
	t.check(bool(server.cmd_party_accept(102).get("ok", false)),
			"recruit joins only after having hit the infected")
	var group_id: int = server.parties.group_of(101)
	t.check(group_id > 0 and group_id == server.parties.group_of(102), "both survivors share one live group")
	var bags_before: int = server.bags.size()
	server._damage_target(leader, {"kind": "zombie", "id": before_join.id}, 500.0)
	t.eq(recruit.progression.combat_xp["melee"], 0,
			"joining after the hit cannot mint party mastery")
	t.eq(leader.progression.combat_xp["melee"], int(before_join.data["xp"]),
			"killer still receives the usual XP")
	t.eq(server.bags.size(), bags_before + 1, "one infected death creates exactly one bag")
	t.eq(recruit.kills, 0, "party members do not receive false kills")

	t.current = "fresh contribution in active group earns its normal assist"
	var active = _walker(server, world)
	server._damage_target(recruit, {"kind": "zombie", "id": active.id}, 1.0)
	t.eq(int(active.contributors[102].get("group", -1)), group_id,
			"contribution is signed using current authoritative group")
	server._damage_target(leader, {"kind": "zombie", "id": active.id}, 500.0)
	var actual: int = int(recruit.progression.combat_xp["melee"])
	t.eq(actual, Party.assist_xp(int(active.data["xp"])),
			"recent equipped contributor earns bounded group assist")
	server._damage_target(leader, {"kind": "zombie", "id": active.id}, 500.0)
	t.eq(recruit.progression.combat_xp["melee"], actual,
			"corpse attacks cannot duplicate mastery")
	t.check(not server.snapshot_for(102)["you"]["party"].has("contributors"),
			"private contribution ledger does not leak to snapshots")

	t.current = "disbanding and recreating a group does not revive old hits"
	var prior = _walker(server, world)
	server._damage_target(recruit, {"kind": "zombie", "id": prior.id}, 1.0)
	t.eq(int(prior.contributors[102].get("group", -1)), group_id,
			"previous hit belongs to original party")
	t.check(bool(server.cmd_party_leave(102).get("ok", false)), "recruit leaves party")
	t.eq(server.parties.group_of(101), 0, "singleton old party is disbanded")
	t.check(bool(server.cmd_party_invite(101, 102).get("ok", false)), "leader creates a fresh party")
	t.check(bool(server.cmd_party_accept(102).get("ok", false)), "recruit rejoins a new group")
	var new_group: int = server.parties.group_of(101)
	t.check(new_group > group_id, "new party has a distinct server identity")
	server._damage_target(leader, {"kind": "zombie", "id": prior.id}, 500.0)
	t.eq(recruit.progression.combat_xp["melee"], actual,
			"changing groups cannot reclassify historical contribution")
