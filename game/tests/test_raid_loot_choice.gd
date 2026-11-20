extends RefCounted
## Players may select a real available reward type on their own raid turn;
## the server decides how much can be received and preserves one physical bag.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const RaidRoundRobin = preload("res://scripts/shared/raid_round_robin.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "contributors choose a raid reward type without duplicating stacks"
	var world := WorldGen.new(93)
	var server := GameServer.new(world, 93)
	server.time = 100.0
	var leader = server.add_player(641, "Raider", "choice-one")
	var partner = server.add_player(642, "Partner", "choice-two")
	var stranger = server.add_player(643, "Stranger", "choice-three")
	var position := _at(world, 900.0, 903.0)
	leader.position = position
	partner.position = position
	stranger.position = position
	var bag_id: int = server._make_bag(position, {"infected_core": 2, "wood_1": 3})
	var bag: Dictionary = server.bags[bag_id]
	var tokens: Array = [RaidLoot.token(leader), RaidLoot.token(partner)]
	RaidLoot.reserve(bag, tokens, server.time)
	t.check(RaidRoundRobin.activate(bag, tokens, 2, server.time),
		"boss bag freezes eligible turn order")
	var snapshot: Dictionary = server.snapshot_for(641)["bags"][0]
	t.eq(snapshot.get("raid_item_choices", []), ["infected_core", "wood_1"],
		"current contributor receives selectable types, not private tokens")
	t.check(not server.snapshot_for(642)["bags"][0].has("raid_item_choices"),
		"non-current contributor cannot inspect the selection list")
	t.check(not server.snapshot_for(643)["bags"][0].has("raid_item_choices"),
		"outsider cannot inspect reserved boss rewards")
	t.check(not snapshot.has("raid_eligible_tokens"), "account identities never replicate")
	t.eq(server.cmd_raid_claim_selected(641, bag_id, "").get("reason"), "invalid_item",
		"empty selection rejected without consuming a turn")
	t.eq(server.cmd_raid_claim_selected(641, bag_id, "x".repeat(97)).get("reason"), "invalid_item",
		"oversized client-controlled item IDs rejected")
	t.eq(server.cmd_raid_claim_selected(641, bag_id, "stone_1").get("reason"), "item_unavailable",
		"client cannot mint a valid item absent from the actual bag")
	t.eq(server.cmd_raid_claim_selected(643, bag_id, "wood_1").get("reason"), "raid_reserved",
		"outsider cannot claim a desired loot type")
	t.eq(server.cmd_raid_claim_selected(642, bag_id, "wood_1").get("reason"), "not_your_turn",
		"party member cannot select during someone else's turn")
	t.eq(bag["items"], {"infected_core": 2, "wood_1": 3},
		"rejected requests neither remove items nor alter original stacks")
	leader.position = _at(world, 940.0, 940.0)
	t.eq(server.cmd_raid_claim_selected(641, bag_id, "wood_1").get("reason"), "too_far",
		"selection is not a remote loot exploit")
	leader.position = position
	var first: Dictionary = server.cmd_raid_claim_selected(641, bag_id, "wood_1")
	t.check(bool(first.get("ok", false)), "first holder chooses wood instead of alphabetic core")
	t.eq(first.get("item", ""), "wood_1", "server honored valid selected type")
	t.eq(first.get("quantity", 0), 2, "first share capped at ceil(original / participants)")
	t.eq(leader.inventory.count("wood_1"), 2, "selected reward reaches only claiming inventory")
	t.eq(int(bag["items"]["wood_1"]), 1, "same original bag retains the unclaimed wood")
	t.eq(server.cmd_raid_claim_selected(641, bag_id, "infected_core").get("reason"),
		"not_your_turn", "a claimant cannot take a second item out of turn")
	var second: Dictionary = server.cmd_raid_claim_selected(642, bag_id, "infected_core")
	t.check(bool(second.get("ok", false)), "next contributor chooses a different resource")
	t.eq(second.get("quantity", 0), 1, "core reward also respects its original split")
	t.eq(partner.inventory.count("infected_core"), 1, "reward moves once")
	t.check(server.cmd_loot(641, bag_id).get("ok", false),
		"plain Q loot still picks the first available type")
	t.eq(leader.inventory.count("infected_core"), 1,
		"keyboard path keeps legacy deterministic behavior")
	t.check(server.cmd_raid_claim_selected(642, bag_id, "wood_1").get("ok", false),
		"last participant claims the final selectable type")
	t.eq(partner.inventory.count("wood_1"), 1, "no loot remains duplicated")
	t.check(not server.bags.has(bag_id), "fully drained bag is removed")
	t.eq(server.cmd_raid_claim_selected(641, bag_id, "wood_1").get("reason"),
		"nothing_there", "replayed selection after removal cannot recreate loot")
	t.eq(leader.inventory.count("wood_1") + partner.inventory.count("wood_1"), 3,
		"all original wood accounted for once")
	t.eq(leader.inventory.count("infected_core") + partner.inventory.count("infected_core"), 2,
		"all original cores accounted for once")

	t.current = "non-round-robin bags and expired turns"
	var ordinary: int = server._make_bag(position, {"wood_1": 1})
	t.eq(server.cmd_raid_claim_selected(641, ordinary, "wood_1").get("reason"),
		"not_active", "selected raid RPC cannot loot an ordinary bag")
	t.eq(server.bags[ordinary]["items"], {"wood_1": 1},
		"ordinary world loot was not consumed by selected raid RPC")
	t.check(server.cmd_loot(641, ordinary).get("ok", false),
		"regular pickup remains functional")
	var expired: int = server._make_bag(position, {"infected_core": 1})
	var expired_bag: Dictionary = server.bags[expired]
	RaidLoot.reserve(expired_bag, tokens, server.time)
	t.check(RaidRoundRobin.activate(expired_bag, tokens, 2, server.time),
		"independent bag starts reserved")
	server.time += RaidLoot.LOCK_SECONDS + 0.01
	t.eq(server.cmd_raid_claim_selected(641, expired, "infected_core").get("reason"),
		"not_active", "expired turn cannot be restarted with a forged item choice")
	t.check(server.cmd_loot(643, expired).get("ok", false),
		"ordinary public loot release still applies after raid reservation")
	var net := Net.new()
	t.check(net.has_method("c_raid_claim_selected"), "selected loot RPC is wired")
	net.free()
