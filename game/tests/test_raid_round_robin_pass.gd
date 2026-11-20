extends RefCounted
## Passing an earned raid turn changes only turn ownership, never reward items.
## The authenticated server owns identity, distance, timing and order.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const RaidRoundRobin = preload("res://scripts/shared/raid_round_robin.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "server-authoritative raid turn pass, never item transfer"
	var world := WorldGen.new(86)
	var server := GameServer.new(world, 86)
	server.time = 100.0
	var leader = server.add_player(501, "Leader", "raid-leader")
	var ally = server.add_player(502, "Ally", "raid-ally")
	var outsider = server.add_player(503, "Outsider", "raid-stranger")
	var position := _at(world, 901.0, 902.0)
	leader.position = position
	ally.position = position
	outsider.position = position
	var bag_id: int = server._make_bag(position, {"infected_core": 2})
	var bag: Dictionary = server.bags[bag_id]
	var identities: Array = [RaidLoot.token(leader), RaidLoot.token(ally)]
	RaidLoot.reserve(bag, identities, server.time)
	t.check(RaidRoundRobin.activate(bag, identities, 2, server.time),
		"two distinct verified contributors receive deterministic turns")
	var original: Dictionary = bag["items"].duplicate(true)
	t.eq(server.cmd_raid_skip_turn(503, bag_id).get("reason"), "raid_reserved",
		"outsider cannot hand off someone else's earned loot")
	t.eq(server.cmd_raid_skip_turn(502, bag_id).get("reason"), "not_your_turn",
		"other eligible player cannot pass someone else's turn")
	t.eq(bag["items"], original, "unauthorized passes cannot change loot contents")
	leader.position = _at(world, 950.0, 951.0)
	t.eq(server.cmd_raid_skip_turn(501, bag_id).get("reason"), "too_far",
		"remote contributor cannot pass from outside pickup reach")
	leader.position = position
	leader.mounted = true
	t.eq(server.cmd_raid_skip_turn(501, bag_id).get("reason"), "mounted",
		"mounted survivors cannot remotely manipulate a bag")
	leader.mounted = false
	t.check(server.cmd_raid_skip_turn(501, bag_id).get("ok", false),
		"the current turn holder voluntarily yields")
	t.eq(bag["items"], original, "passing leaves all items in the original world bag")
	t.eq(server.cmd_raid_skip_turn(501, bag_id).get("reason"), "not_your_turn",
		"the same player cannot immediately skip another player's turn")
	t.check(not bool(server.snapshot_for(501)["bags"][0].get("raid_your_turn", true)),
		"first player sees their turn end")
	t.check(bool(server.snapshot_for(502)["bags"][0].get("raid_your_turn", false)),
		"next player can immediately act")
	t.check(not server.snapshot_for(503)["bags"][0].has("raid_eligible_tokens"),
		"public snapshots never disclose private account tokens")
	t.eq(ally.inventory.count("infected_core"), 0, "skip itself gives no loot")
	t.check(server.cmd_loot(502, bag_id).get("ok", false),
		"next player can claim a real bounded share")
	t.eq(ally.inventory.count("infected_core"), 1,
		"only one boss reward was transferred to the next player")
	t.eq(int(server.bags[bag_id]["items"].get("infected_core", 0)), 1,
		"remaining share stays in the one original bag")
	t.check(server.cmd_loot(501, bag_id).get("ok", false),
		"turn returns to the first contributor after a successful claim")
	t.eq(leader.inventory.count("infected_core"), 1,
		"remaining reward is claimable exactly once")
	t.check(not server.bags.has(bag_id), "depleted bag is removed after claims")
	t.eq(server.cmd_raid_skip_turn(501, bag_id).get("reason"), "nothing_there",
		"stale RPC after bag removal cannot resurrect a turn")

	t.current = "expired reservations and authenticated reconnects"
	var next_id: int = server._make_bag(position, {"infected_core": 3})
	var next_bag: Dictionary = server.bags[next_id]
	RaidLoot.reserve(next_bag, identities, server.time)
	t.check(RaidRoundRobin.activate(next_bag, identities, 4, server.time),
		"new bag receives independent turn order")
	server.remove_player(501)
	var reconnected = server.add_player(504, "LeaderReturn", "raid-leader")
	reconnected.position = position
	t.check(server.cmd_raid_skip_turn(504, next_id).get("ok", false),
		"same authenticated identity keeps earned passing rights after reconnect")
	t.eq(server.cmd_raid_skip_turn(501, next_id).get("reason"), "dead",
		"disconnected old network peer cannot replay the pass")
	server.time += RaidLoot.LOCK_SECONDS + 0.01
	t.eq(server.cmd_raid_skip_turn(502, next_id).get("reason"), "not_active",
		"after reservation expires the round-robin turn cannot be manipulated")
	t.eq(next_bag["items"], {"infected_core": 3},
		"yield and expiry never destroy unclaimed rewards")
	var net := Net.new()
	t.check(net.has_method("c_raid_skip_turn"), "network command is exposed")
	net.free()
