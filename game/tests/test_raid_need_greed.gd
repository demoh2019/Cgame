extends RefCounted
## Need/Greed resolves on the real server, with no cloned reward containers.
## Only the existing raid bag inventory is reduced by successful pickups.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const RaidNeedGreed = preload("res://scripts/shared/raid_need_greed.gd")
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _boss(sim, world):
	var enemy := Zombie.new(sim.new_id(), "brute", _at(world, 902.0, 900.0), -1)
	RaidEncounter.empower(enemy)
	sim.zombies[enemy.id] = enemy
	return enemy


func _defeat(sim, world, helper, killer) -> int:
	var enemy = _boss(sim, world)
	sim._damage_target(helper, {"kind": "zombie", "id": enemy.id}, 3.0)
	sim._damage_target(killer, {"kind": "zombie", "id": enemy.id}, 1000.0)
	return int(sim.bags.keys()[0]) if not sim.bags.is_empty() else -1


func run(t) -> void:
	t.current = "malformed raid lock never creates a broken or endless election"
	var valid_core_bag: Dictionary = {"items": {"infected_core": 1},
		"raid_reserved_until": 75.0}
	var voters: Array = ["account:a", "account:b"]
	for broken_lock in [NAN, INF, "75", -1.0, 0.0]:
		var invalid_bag: Dictionary = valid_core_bag.duplicate(true)
		invalid_bag["raid_reserved_until"] = broken_lock
		t.check(not RaidNeedGreed.activate(invalid_bag, voters, 42, 0.0),
			"invalid or expired raid reservation cannot start a vote")
		t.check(not invalid_bag.has("raid_need_greed"),
			"rejected election leaves physical loot bag untouched")
	var short_bag: Dictionary = valid_core_bag.duplicate(true)
	short_bag["raid_reserved_until"] = 4.0
	t.check(RaidNeedGreed.activate(short_bag, voters, 42, 0.0),
		"short but valid reservation can still hold a vote")
	t.eq(short_bag["raid_need_greed"]["until"], 4.0,
		"ballot cannot outlive its underlying exclusive raid loot window")
	t.eq(RaidNeedGreed.vote(short_bag, null, "need", 0.0).get("reason", ""),
		"not_eligible", "missing identity cannot submit a vote")
	t.eq(RaidNeedGreed.visible(short_bag, null, 0.0), {},
		"missing identity receives no private ballot data")
	t.check(bool(RaidNeedGreed.protection(short_bag, null, 0.0).get("locked", false)),
		"missing identity cannot bypass trophy protection")

	t.current = "valid, bounded, immutable player ballots"
	var world := WorldGen.new(47)
	var server := GameServer.new(world, 47)
	var captain = server.add_player(101, "Captain", "core-captain")
	var ally = server.add_player(102, "Ally", "core-ally")
	var outsider = server.add_player(103, "Ninja", "core-ninja")
	for player in [captain, ally, outsider]:
		player.position = _at(world, 901.0, 900.0)
		player.inventory.add("club_1", 1)
		player.inventory.equip("club_1")
	t.check(server.cmd_party_invite(101, 102).get("ok", false),
		"server accepts a nearby party invitation")
	t.check(server.cmd_party_accept(102).get("ok", false), "ally joins group")
	t.eq(server.cmd_party_loot_mode(102, "need_greed").get("reason", ""),
		"leader_only", "a teammate cannot force the leader's raid loot setting")
	t.check(server.cmd_party_loot_mode(101, "need_greed").get("ok", false),
		"leader opts future raid drops into Need/Greed")
	t.eq(server.snapshot_for(102)["you"]["party"]["loot_mode"], "need_greed",
		"contributors see their party's frozen future loot mode")
	t.eq(server.snapshot_for(103)["you"]["party"]["loot_mode"], "free",
		"strangers cannot see someone else's future raid setting")
	var bag_id: int = _defeat(server, world, ally, captain)
	t.check(bag_id > 0, "boss death produces one real loot bag")
	if bag_id < 0:
		return
	t.eq(server.bags.size(), 1, "Need/Greed never produces personal loot copies")
	var bag: Dictionary = server.bags[bag_id]
	t.check(bag.has("raid_need_greed"), "server freezes eligible raid voters at kill")
	t.eq(str(bag["raid_need_greed"]["status"]), "voting",
		"voting begins without picking a random winner prematurely")
	t.eq((bag["raid_need_greed"]["eligible"] as Array).size(), 2,
		"only real combat contributors enter the frozen ballot")
	var original_core: int = int(bag["items"]["infected_core"])
	t.check(original_core > 0, "the physical bag still holds the entire core stack")
	t.near(RaidLoot.remaining(bag, server.time), 75.0, 0.001,
		"existing raid entitlement remains intact")
	var ally_view: Dictionary = server.snapshot_for(102)["bags"][0]
	var outsider_view: Dictionary = server.snapshot_for(103)["bags"][0]
	t.eq(str(ally_view["raid_need_greed"]["status"]), "voting",
		"eligible contributor sees an actionable private ballot")
	t.check(not outsider_view.has("raid_need_greed"),
		"outsider learns nothing about vote choices, account tokens or rolls")
	t.check(not ally_view.has("raid_eligible_tokens") and
			not ally_view.has("eligible") and not ally_view.has("votes"),
		"account identities and private ballots never reach the network")
	t.eq(server.cmd_raid_vote(103, bag_id, "need").get("reason", ""),
		"raid_reserved", "non-contributor cannot vote on reserved loot")
	var saved_position: Vector3 = ally.position
	ally.position = _at(world, 970.0, 900.0)
	t.eq(server.cmd_raid_vote(102, bag_id, "need").get("reason", ""),
		"too_far", "frozen contributor cannot cast votes from far away")
	ally.position = saved_position
	t.eq(server.cmd_raid_vote(102, bag_id, "admin").get("reason", ""),
		"invalid_choice", "invented choices cannot be submitted")
	t.check(server.cmd_raid_vote(102, bag_id, "need").get("ok", false),
		"eligible contributor casts Need once")
	t.eq(server.cmd_raid_vote(102, bag_id, "greed").get("reason", ""),
		"already_voted", "replayed or changed ballot cannot manipulate the result")
	t.eq(str(server.snapshot_for(102)["bags"][0]["raid_need_greed"]["your_vote"]),
		"need", "the voter sees only their own locked choice")
	t.check(server.cmd_raid_vote(101, bag_id, "greed").get("ok", false),
		"other member votes Greed; the ballot resolves immediately")
	t.eq(str(bag["raid_need_greed"]["status"]), "awarded",
		"all votes close the roll before the timeout")
	t.eq(str(bag["raid_need_greed"]["winner"]), RaidLoot.token(ally),
		"Need has absolute priority over a Greed vote")
	t.eq(server.cmd_raid_vote(101, bag_id, "need").get("reason", ""),
		"vote_closed", "winner cannot be rerolled by another ballot")
	t.check(bool(server.snapshot_for(102)["bags"][0]["raid_need_greed"]["your_win"]),
		"winner receives their own personal trophy notification")
	t.check(not bool(server.snapshot_for(101)["bags"][0]["raid_need_greed"]["your_win"]),
		"loser sees only whether they won, never another account token")

	t.current = "trophy lock protects one original stack while ordinary supplies remain lootable"
	t.check(not bool(server.snapshot_for(101)["bags"][0].get("raid_your_turn", false)),
		"Need/Greed does not become Round Robin")
	var loser_loot: Dictionary = server.cmd_loot(101, bag_id)
	t.check(loser_loot.get("ok", false) and loser_loot.get("core_locked", false),
		"loser can still collect silver, bars and supplies from the same bag")
	t.eq(captain.inventory.count("infected_core"), 0,
		"loser never receives protected cores")
	t.eq(int(server.bags[bag_id]["items"]["infected_core"]), original_core,
		"protected core stack is not reduced by another player's pickup")
	t.eq(server.cmd_loot(101, bag_id).get("reason", ""),
		"raid_winner_reserved", "loser cannot take a core-only remaining bag")
	var before: int = ally.inventory.count("infected_core")
	t.check(server.cmd_loot(102, bag_id).get("ok", false),
		"authenticated winner can claim the original core stack")
	t.eq(ally.inventory.count("infected_core") - before, original_core,
		"winner's real inventory gains the physical trophy stack only once")
	t.check(not server.bags.has(bag_id), "single shared bag disappears after pickup")
	t.eq(server.cmd_loot(102, bag_id).get("reason", ""),
		"nothing_there", "replaying the pickup does not duplicate rare loot")

	t.current = "changing the future mode never changes a live bag's frozen election"
	var second_id: int = _defeat(server, world, ally, captain)
	t.check(second_id > 0 and server.bags[second_id].has("raid_need_greed"),
		"second real raid starts another independent vote")
	t.check(server.cmd_party_loot_mode(101, "free").get("ok", false),
		"leader can revert future drops to free pickup")
	t.check(server.bags[second_id].has("raid_need_greed"),
		"already-dropped loot retains its voting rules")
	t.check(server.cmd_raid_vote(101, second_id, "pass").get("ok", false),
		"first contributor passes a frozen vote")
	t.check(server.cmd_raid_vote(102, second_id, "pass").get("ok", false),
		"second contributor passes the roll too")
	t.eq(str(server.bags[second_id]["raid_need_greed"]["status"]), "free",
		"all-pass result releases cores to eligible first pick")
	t.check(server.cmd_loot(101, second_id).get("ok", false),
		"eligible survivor gets normal unprotected loot after all pass")
	t.check(not server.bags.has(second_id), "free pickup still consumes exactly one bag")

	t.current = "unanswered rolls expire; normal raid lock still governs outsiders"
	t.check(server.cmd_party_loot_mode(101, "need_greed").get("ok", false),
		"leader may opt into voting again for later boss")
	var third_id: int = _defeat(server, world, ally, captain)
	t.eq(str(server.bags[third_id]["raid_need_greed"]["status"]), "voting",
		"new independent loot starts with no votes")
	server.time += RaidNeedGreed.VOTE_SECONDS + 0.01
	var no_votes: Dictionary = RaidNeedGreed.resolve(server.bags[third_id], server.time)
	t.eq(str(no_votes["status"]), "free",
		"missing votes count as Pass after the bounded timer")
	t.eq(server.cmd_loot(103, third_id).get("reason", ""), "raid_reserved",
		"vote deadline does not bypass the original raid reservation")
	t.check(server.cmd_loot(102, third_id).get("ok", false),
		"eligible player may claim publicly released cores")
	t.check(not server.bags.has(third_id), "same physical bag is consumed")

	t.current = "75-second deadline releases unclaimed cores to everybody"
	var fourth_id: int = _defeat(server, world, ally, captain)
	t.check(server.bags[fourth_id].has("raid_need_greed"),
		"fourth boss still opens a frozen vote")
	server.time += RaidLoot.LOCK_SECONDS + 0.01
	t.check(server.cmd_loot(103, fourth_id).get("ok", false),
		"after the raid reservation, outsider may loot all remaining items")
	t.check(not server.bags.has(fourth_id), "public loot pickup has no second payout")
	t.eq(server.cmd_raid_vote(102, fourth_id, "need").get("reason", ""),
		"no_vote", "expired and consumed bag rejects a late vote")

	t.current = "future free mode retains legacy boss drop semantics"
	t.check(server.cmd_party_loot_mode(101, "free").get("ok", false),
		"leader restores normal gameplay")
	var free_id: int = _defeat(server, world, ally, captain)
	t.check(not server.bags[free_id].has("raid_need_greed"),
		"free mode never creates a ballot")
	t.check(server.cmd_loot(101, free_id).get("ok", false),
		"existing default free raid bag still works")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net.has_method("c_raid_vote"),
		"authenticated Need/Greed vote RPC is registered")
	net.free()
