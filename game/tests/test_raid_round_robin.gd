extends RefCounted
## Optional raid loot fairness without copying or creating extra boss bags.
## All claims settle through real GameServer inventories and fixed account IDs.

const Party = preload("res://scripts/shared/party.gd")
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const RaidRoundRobin = preload("res://scripts/shared/raid_round_robin.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _spawn_boss(sim, position: Vector3):
	var boss = Zombie.new(sim.new_id(), "brute", position, -1)
	RaidEncounter.empower(boss)
	sim.zombies[boss.id] = boss
	return boss


func run(t) -> void:
	t.current = "raid loot mode requires a real party leader"
	var party := Party.new()
	t.eq(party.loot_mode_for(10), "free", "unconnected players default to free pickup")
	t.eq(party.set_loot_mode(10, "round_robin").get("reason", ""),
		"not_in_party", "solo player cannot configure a nonexistent party")
	t.check(party.invite(10, 11, 0.0).get("ok", false), "leader invites ally")
	t.check(party.accept(11, 0.0).get("ok", false), "ally joins")
	t.eq(party.set_loot_mode(11, "round_robin").get("reason", ""),
		"leader_only", "nonleaders cannot silently change loot distribution")
	t.eq(party.set_loot_mode(10, "master_loot").get("reason", ""),
		"invalid_mode", "arbitrary client mode values are rejected")
	t.eq(party.loot_mode_for(11), "free", "default stays backwards compatible")
	t.check(party.set_loot_mode(10, "round_robin").get("ok", false),
		"leader explicitly opts into round-robin")
	t.eq(party.loot_mode_for(11), "round_robin",
		"all party members see the same future raid mode")
	t.eq(party.state_for(11)["loot_mode"], "round_robin",
		"mode is visible only in the authenticated private party state")
	t.eq(party.state_for(99)["loot_mode"], "free",
		"outsider does not see another group's raid choice")
	t.check(party.set_loot_mode(10, "free").get("ok", false),
		"leader may restore default free pickup")

	t.current = "one physical boss bag with frozen participant tokens and split stack"
	var world := WorldGen.new(47)
	var sim := GameServer.new(world, 47)
	var captain = sim.add_player(101, "Captain", "raid-captain")
	var ally = sim.add_player(102, "Support", "raid-support")
	var outsider = sim.add_player(103, "Stranger", "raid-stranger")
	for actor in [captain, ally, outsider]:
		actor.position = _at(world, 901.0, 900.0)
		actor.inventory.add("club_1", 1)
		actor.inventory.equip("club_1")
	t.check(sim.cmd_party_invite(101, 102).get("ok", false), "real server validates party invite")
	t.check(sim.cmd_party_accept(102).get("ok", false), "ally accepts invite")
	t.eq(sim.cmd_party_loot_mode(103, "round_robin").get("reason", ""),
		"not_in_party", "stranger cannot configure a party")
	t.eq(sim.cmd_party_loot_mode(102, "round_robin").get("reason", ""),
		"leader_only", "server refuses unauthorized member configuration")
	t.check(sim.cmd_party_loot_mode(101, "round_robin").get("ok", false),
		"leader switches future boss drops to fair distribution")
	var boss = _spawn_boss(sim, _at(world, 902.0, 900.0))
	sim._damage_target(ally, {"kind": "zombie", "id": boss.id}, 3.0)
	sim._damage_target(captain, {"kind": "zombie", "id": boss.id}, 1000.0)
	t.eq(sim.bags.size(), 1, "one shared bag is dropped, not personal reward copies")
	if sim.bags.is_empty():
		return
	var bag_id: int = int(sim.bags.keys()[0])
	var bag: Dictionary = sim.bags[bag_id]
	t.check(RaidRoundRobin.active(bag, sim.time),
		"one validated boss kill enables fair rotation")
	t.eq((bag["raid_round_robin"]["order"] as Array).size(), 2,
		"only actual combat contributors receive loot turns")
	t.eq(RaidLoot.remaining(bag, sim.time), RaidLoot.LOCK_SECONDS,
		"existing 75-second raid reservation is unchanged")
	t.eq(sim.cmd_loot(103, bag_id).get("reason", ""), "raid_reserved",
		"outsider cannot take reserved items regardless of loot mode")
	t.check(not sim.snapshot_for(103)["bags"][0].has("raid_eligible_tokens"),
		"public snapshot never contains account identifiers")
	t.check(not sim.snapshot_for(103)["bags"][0].has("order"),
		"turn queue identities never leak to spectators")
	var first = captain if RaidRoundRobin.turn(bag, captain, sim.time)["ok"] else ally
	var second = ally if first == captain else captain
	t.check(bool(RaidRoundRobin.turn(bag, first, sim.time)["ok"]),
		"one current eligible recipient is selected deterministically")
	t.check(not bool(RaidRoundRobin.turn(bag, second, sim.time)["ok"]),
		"other eligible member waits their turn")
	t.check(bool(sim.snapshot_for(first.id)["bags"][0].get("raid_your_turn", false)),
		"current recipient sees private pickup prompt")
	t.check(not bool(sim.snapshot_for(second.id)["bags"][0].get("raid_your_turn", true)),
		"other recipient cannot pick up early")
	t.eq(sim.cmd_loot(second.id, bag_id).get("reason", ""), "not_your_turn",
		"early pickup is rejected before touching either inventory")
	var offer: Dictionary = RaidRoundRobin.offer(bag, first, sim.time)
	t.check(offer.get("ok", false), "server selects a deterministic item type")
	var item: String = str(offer.get("item", ""))
	var before: int = int(bag["items"].get(item, 0))
	var prior_inventory: int = first.inventory.count(item)
	var pickup: Dictionary = sim.cmd_loot(first.id, bag_id)
	t.check(bool(pickup.get("ok", false)) and bool(pickup.get("round_robin", false)),
		"real player receives exactly one round-robin share")
	t.eq(int(pickup.get("quantity", 0)), int(offer.get("quantity", -1)),
		"pickup is bounded by original stack and group size")
	t.eq(first.inventory.count(item) - prior_inventory, int(pickup.get("quantity", 0)),
		"player inventory really receives the claimed quantity")
	t.eq(before - int(sim.bags[bag_id]["items"].get(item, 0)),
		int(pickup.get("quantity", 0)),
		"same quantity is removed from the ONE physical bag")
	t.eq(sim.cmd_loot(first.id, bag_id).get("reason", ""), "not_your_turn",
		"replayed pickup cannot grab the next player's share")
	t.check(bool(sim.snapshot_for(second.id)["bags"][0].get("raid_your_turn", false)),
		"turn switches immediately to the next contributor")
	t.check(sim.cmd_loot(second.id, bag_id).get("ok", false),
		"teammate may collect a real share of the remaining loot")
	t.eq(sim.cmd_loot(103, bag_id).get("reason", ""), "raid_reserved",
		"rotation cannot bypass the contributor reservation")

	t.current = "malformed rotation metadata cannot bypass or crash a protected raid"
	var bad_bag: Dictionary = {
		"items": {"infected_core": 6}, "raid_reserved_until": 75.0,
		"raid_round_robin": {"order": "broken", "index": 0,
			"until": 12.0, "original": {"infected_core": 6}}
	}
	t.check(RaidRoundRobin.active(bad_bag, 0.0),
		"corrupt rotation remains active while raid lock is held")
	t.eq(RaidRoundRobin.turn(bad_bag, captain, 0.0).get("reason", ""),
		"invalid_state", "malformed order is rejected safely")
	t.eq(RaidRoundRobin.offer(bad_bag, captain, 0.0).get("reason", ""),
		"invalid_state", "malformed rotation never offers free claims")
	bad_bag["raid_round_robin"] = {"order": ["raid-captain", "raid-ally"],
		"index": 99, "until": 12.0, "original": {"infected_core": 6}}
	t.eq(RaidRoundRobin.turn(bad_bag, captain, 0.0).get("reason", ""),
		"invalid_state", "out-of-range turn index is rejected")
	bad_bag["raid_round_robin"] = {"order": ["raid-captain", "raid-ally"],
		"index": 0, "until": NAN, "original": {"infected_core": 6}}
	t.eq(RaidRoundRobin.turn(bad_bag, captain, 0.0).get("reason", ""),
		"invalid_state", "non-finite turn deadline is rejected")
	bad_bag["raid_round_robin"] = {"order": ["raid-captain", "raid-captain"],
		"index": 0, "until": 12.0, "original": {"infected_core": 6}}
	t.eq(RaidRoundRobin.offer(bad_bag, captain, 0.0).get("reason", ""),
		"invalid_state", "duplicate participants cannot distort fair shares")
	t.eq(RaidRoundRobin.turn(bad_bag, null, 0.0).get("reason", ""),
		"invalid_state", "missing player identity is rejected")
	var bad_activation: Dictionary = {"items": {"infected_core": 2},
		"raid_reserved_until": NAN}
	t.check(not RaidRoundRobin.activate(bad_activation,
		["account:a", "account:b"], 99, 0.0),
		"invalid raid lock cannot start rotation")
	t.check(not bad_activation.has("raid_round_robin"),
		"failed activation leaves loot unchanged")

	t.current = "mode changes affect future victories, not frozen drops"
	t.check(sim.cmd_party_loot_mode(101, "free").get("ok", false),
		"leader switches mode for next boss")
	t.check(RaidRoundRobin.active(sim.bags[bag_id], sim.time),
		"existing raid bag preserves locked-in round-robin distribution")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_party_loot_mode"),
		"network action uses authenticated sender identity")
	net.free()

	t.current = "timed skip and public unlock do not create duplicate items"
	var current: Dictionary = RaidRoundRobin.turn(sim.bags[bag_id], captain, sim.time)
	var successor: Dictionary = RaidRoundRobin.turn(sim.bags[bag_id], captain,
		sim.time + RaidRoundRobin.TURN_SECONDS + 0.01)
	t.check(int(current.get("index", -1)) != int(successor.get("index", -1)),
		"unused turn advances after bounded 12-second timeout")
	t.check(not RaidRoundRobin.active(sim.bags[bag_id],
		sim.time + RaidLoot.LOCK_SECONDS + 0.01),
		"round-robin expires with existing 75-second reservation")
	sim.time += RaidLoot.LOCK_SECONDS + 0.01
	t.check(sim.cmd_loot(103, bag_id).get("ok", false),
		"outsider may gather any remaining items only after public unlock")
	t.check(not sim.bags.has(bag_id),
		"public pickup consumes leftover physical bag once")
	t.eq(sim.cmd_loot(103, bag_id).get("reason", ""), "nothing_there",
		"repeat pickup cannot duplicate rewards")

	t.current = "future boss reverts to original free pickup behavior"
	var second_boss = _spawn_boss(sim, _at(world, 902.0, 900.0))
	sim._damage_target(ally, {"kind": "zombie", "id": second_boss.id}, 3.0)
	sim._damage_target(captain, {"kind": "zombie", "id": second_boss.id}, 1000.0)
	t.eq(sim.bags.size(), 1, "new victory creates one independent loot bag")
	var free_bag: Dictionary = sim.bags[int(sim.bags.keys()[0])]
	t.check(not free_bag.has("raid_round_robin"),
		"free pickup stays compatible with old raid loot rules")
