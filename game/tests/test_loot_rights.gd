extends RefCounted
## PvE kill ownership, party sharing, timer boundaries and PvP full loot.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const LootRights = preload("res://scripts/shared/loot_rights.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "loot reservation policy"
	t.eq(LootRights.reservation(0, [2], 0.0), {}, "invalid owner never claims loot")
	var rights: Dictionary = LootRights.reservation(11, [11, 12, 12, -1, "fake"], 3.0)
	t.eq(rights["allowed_peers"], [11, 12], "only unique positive peer IDs are reserved")
	t.check(LootRights.can_loot(rights, 12, 3.0), "party member can loot")
	t.check(not LootRights.can_loot(rights, 13, 20.99), "outsider denied just before expiry")
	t.check(LootRights.can_loot(rights, 13, 21.0), "reservation expires exactly at boundary")
	t.check(LootRights.can_loot({}, 13, 0.0), "unreserved loot remains public")

	t.current = "authoritative group access and private snapshot"
	var world := WorldGen.new(154)
	var server := GameServer.new(world, 154)
	var leader = server.add_player(11, "Leader")
	var ally = server.add_player(12, "Ally")
	var stranger = server.add_player(13, "Stranger")
	leader.position = _at(world, 200.0, 200.0)
	ally.position = _at(world, 201.0, 200.0)
	stranger.position = _at(world, 200.0, 201.0)
	t.check(server.cmd_party_invite(11, 12)["ok"], "nearby party invite succeeds")
	t.check(server.cmd_party_accept(12)["ok"], "party member accepts")
	var bag_id: int = server._make_bag(leader.position, {"silver": 9}, 11)
	t.check(bag_id > 0, "owner receives a real bag ID")
	var bag: Dictionary = server.bags[bag_id]
	t.eq(bag["allowed_peers"], [11, 12], "server captures roster at the drop")
	var stranger_view: Dictionary = server.snapshot_for(13)["bags"][0]
	t.check(stranger_view["reserved"] and not stranger_view["can_loot"],
		"other players see a locked bag")
	t.check(not stranger_view.has("allowed_peers"), "private party IDs never replicate")
	t.check(stranger_view["reserved_seconds"] > 0.0, "client can show lock countdown")
	var ally_view: Dictionary = server.snapshot_for(12)["bags"][0]
	t.check(ally_view["reserved"] and ally_view["can_loot"], "member sees available loot")
	var outsider_before: int = stranger.inventory.count("silver")
	t.eq(server.cmd_loot(13, bag_id)["reason"], "reserved", "outsider loot RPC denied")
	t.eq(stranger.inventory.count("silver"), outsider_before, "rejected RPC never grants items")
	t.check(server.bags.has(bag_id), "rejected RPC never destroys the bag")
	t.check(server.cmd_loot(12, bag_id)["ok"], "current party member can collect")
	t.eq(ally.inventory.count("silver"), 9, "ally receives exact amount once")
	t.check(not server.bags.has(bag_id), "fully collected bag disappears")
	t.eq(server.cmd_loot(12, bag_id)["reason"], "nothing_there", "no replay after collection")

	t.current = "party roster frozen at drop and timer release"
	var solo_id: int = server._make_bag(leader.position, {"silver": 6}, 11)
	server.parties.leave(12)
	t.check(server.cmd_loot(12, solo_id)["ok"], "leaving later does not invalidate old share")
	var later_id: int = server._make_bag(leader.position, {"silver": 7}, 11)
	t.eq(server.cmd_loot(12, later_id)["reason"], "reserved", "new bag excludes former member")
	t.eq(server.cmd_loot(13, later_id)["reason"], "reserved", "outsider is still blocked")
	server.time += LootRights.RESERVATION_SECONDS
	var opened_view: Dictionary = server.snapshot_for(13)["bags"][0]
	t.check(not opened_view["reserved"] and opened_view["can_loot"],
		"expired bags become publicly visible and lootable")
	t.check(server.cmd_loot(13, later_id)["ok"], "bag becomes public after timer")
	t.eq(stranger.inventory.count("silver"), outsider_before + 7, "public loot grants exactly once")

	t.current = "PvP death bags stay public"
	var public_id: int = server._make_bag(leader.position, {"silver": 3})
	t.check(server.cmd_loot(13, public_id)["ok"], "unreserved full-loot bag can be claimed by anyone")
	t.eq(stranger.inventory.count("silver"), outsider_before + 10, "public bags give expected silver")

	t.current = "zombie kills reserve loot for actual killer"
	var before_ids: Array = server.bags.keys()
	var infected = Zombie.new(server.new_id(), "walker", _at(world, 200.0, 200.0))
	server.zombies[infected.id] = infected
	server._damage_target(leader, {"kind": "zombie", "id": infected.id}, 1000.0)
	var zombie_bag_id: int = -1
	for id in server.bags.keys():
		if not before_ids.has(id):
			zombie_bag_id = int(id)
	t.check(zombie_bag_id != -1, "server-spawned PvE kill creates a bag")
	if zombie_bag_id != -1:
		t.eq(server.bags[zombie_bag_id]["allowed_peers"], [11],
			"only the killing player owns a post-party kill")
		t.eq(server.cmd_loot(13, zombie_bag_id)["reason"], "reserved",
			"enemy cannot steal newly spawned zombie loot")
