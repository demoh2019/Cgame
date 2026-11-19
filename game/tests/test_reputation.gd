extends RefCounted
## End-to-end persistent NPC reputation, authenticated PvE and vendor prices.

const Reputation = preload("res://scripts/shared/reputation.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const Net = preload("res://scripts/shared/net.gd")


func _hub(server, player) -> void:
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	player.position = Vector3(hub.x, server.world.height_at(hub.x, hub.y), hub.y)


func _kill(server, player, zombie_type: String, elite: bool = false,
		raid: bool = false):
	var zombie = Zombie.new(server.new_id(), zombie_type,
		player.position + Vector3(4.0, 0.0, 0.0))
	if elite:
		zombie.become_elite()
	if raid:
		RaidEncounter.empower(zombie)
	server.zombies[zombie.id] = zombie
	server._damage_target(player, {"kind": "zombie", "id": zombie.id}, 5000.0)
	return zombie


func run(t) -> void:
	t.current = "finite server-owned reputation rules"
	t.check(Reputation.valid_points(0), "fresh survivor can begin at rank zero")
	t.check(Reputation.valid_points(12.0), "integral JSON float is backward-compatible")
	for invalid in [-1, 1.5, NAN, INF, "500", true, Reputation.MAX_RENOWN + 1]:
		t.check(not Reputation.valid_points(invalid), "invalid reputation payload rejected")
	t.eq(Reputation.title(0), "Newcomer", "unranked survivor has default name")
	t.eq(Reputation.rank(39), 0, "one point below first tier is still Newcomer")
	t.eq(Reputation.rank(40), 1, "forty renown unlocks Settler")
	t.eq(Reputation.rank(160), 2, "experienced survivor becomes Ranger")
	t.eq(Reputation.rank(500), 3, "veteran survivor becomes Warden")
	t.eq(Reputation.discount_percent(0), 0, "newcomer pays normal camp prices")
	t.eq(Reputation.discount_percent(40), 10, "settler saves ten percent")
	t.eq(Reputation.discount_percent(160), 15, "ranger saves fifteen percent")
	t.eq(Reputation.discount_percent(500), 20, "wardens save capped twenty percent")
	t.eq(Reputation.next_threshold(40), 160, "next milestone is explicit")
	t.eq(Reputation.apply_earned(9998, 35), Reputation.MAX_RENOWN,
		"reputation cannot overflow its progression cap")
	t.eq(Reputation.apply_earned(5, -100), 5, "negative earned points cannot lower renown")
	t.eq(Reputation.kill_points("unknown", false, false), 0,
		"unknown enemy type never earns renown")
	t.eq(Reputation.buy_price(12, 1, 0), 12, "normal survival water price unchanged")
	t.eq(Reputation.buy_price(12, 1, 40), 11, "earned rank lowers water price")
	t.eq(Reputation.buy_price(18, 2, 500), 30,
		"wardens get rounded, bounded multi-item buy pricing")
	t.eq(Reputation.buy_price(18, 0, 500), -1,
		"invalid quantity cannot create a zero-price transaction")

	t.current = "server rewards only actual infected deaths, never replay hits"
	var server := GameServer.new(WorldGen.new(81), 81)
	var player = server.add_player(1441, "Survivor")
	var stranger = server.add_player(1442, "Uninvolved")
	_hub(server, player)
	_hub(server, stranger)
	t.eq(player.renown, 0, "new player has zero reputation")
	var dead_walker = _kill(server, player, "walker")
	t.eq(player.renown, 1, "real walker kill awards one renown")
	server._damage_target(player, {"kind": "zombie", "id": dead_walker.id}, 9999.0)
	t.eq(player.renown, 1, "already-dead enemy cannot grant repeated renown")
	_kill(server, player, "runner")
	t.eq(player.renown, 3, "runner kill awards higher tier renown")
	_kill(server, player, "brute", true)
	t.eq(player.renown, 12, "elite brute grants its one-time difficulty bonus")
	var boss = _kill(server, player, "brute", false, true)
	t.eq(player.renown, 51, "confirmed raid boss defeat grants higher renown")
	server._damage_target(player, {"kind": "zombie", "id": boss.id}, 5000.0)
	t.eq(player.renown, 51, "raid bonus cannot be replayed after death")
	t.eq(stranger.renown, 0, "idle nearby stranger has no free reputation")
	t.check(player.dirty_character, "gained reputation is scheduled for Nakama save")
	var snap: Dictionary = server.snapshot_for(player.id)["you"]
	t.eq(snap["renown"], 51, "server snapshot exposes real private score")
	t.eq(snap["renown_rank"], "Settler", "server snapshot exposes rank title")
	t.eq(snap["vendor_discount"], 10, "client receives authoritative discount percent")
	t.eq(server.snapshot_for(stranger.id)["you"]["renown"], 0,
		"other client cannot read private reputation balance")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "renown", "peer": player.id}, player.id),
		"renown award visible to the actual recipient")
	t.check(not net._event_visible_to({"type": "renown", "peer": player.id}, stranger.id),
		"other players cannot receive private renown notifications")
	net.free()

	t.current = "NPC purchases use player's server-owned rank only"
	_hub(server, player)
	player.inventory.add("silver", 120)
	var before_silver: int = player.inventory.count("silver")
	var bought: Dictionary = server.cmd_vendor(player.id, "water_bottle", 1, true)
	t.check(bool(bought.get("ok", false)), "ranked survivor can buy hub water")
	t.eq(int(bought["silver_delta"]), -11, "authoritative trade charges ranked price")
	t.eq(before_silver - player.inventory.count("silver"), 11,
		"transaction actually removes discounted price")
	t.eq(player.inventory.count("water_bottle"), 3, "one water bottle added to starter stock")
	var newcomer_price: Dictionary = server.cmd_vendor(stranger.id, "water_bottle", 1, true)
	t.eq(newcomer_price["reason"], "insufficient_silver",
		"unranked player with no silver cannot inherit a nearby player's discount")
	stranger.inventory.add("silver", 12)
	newcomer_price = server.cmd_vendor(stranger.id, "water_bottle", 1, true)
	t.eq(int(newcomer_price["silver_delta"]), -12, "newcomer pays full water price")
	player.inventory.add("scrap", 1)
	var sale: Dictionary = server.cmd_vendor(player.id, "scrap", 1, false)
	t.eq(int(sale["silver_delta"]), int(Vendor.SELL_PRICES["scrap"]),
		"selling remains full fixed price; discount cannot inflate proceeds")
	var before_denied: Dictionary = player.inventory.to_dict()
	var denied: Dictionary = server.cmd_vendor(player.id, "canned_food", 50, true)
	t.eq(denied["reason"], "insufficient_silver",
		"unauthorized bulk purchase cannot mint supplies")
	t.eq(player.inventory.to_dict(), before_denied,
		"failed discounted vendor purchase rolls back atomically")
	# The ranked transaction also must not consume silver if the purchased
	# item cannot enter a full backpack.
	var roomless := Inventory.new(1)
	roomless.add("silver", Defs.stack_size("silver"))
	var full_before: Dictionary = roomless.to_dict()
	var impossible: Dictionary = Vendor.transact(roomless, "canned_food", 1, true, 500)
	t.eq(impossible["reason"], "no_space", "ranked NPC cannot partially sell into a full backpack")
	t.eq(roomless.to_dict(), full_before, "failed ranked purchase preserves all silver")

	t.current = "criminal notoriety never bypasses reputation price rules"
	var criminal_bag := Inventory.new(3)
	criminal_bag.add("silver", 100)
	var crime_buy: Dictionary = Vendor.transact(criminal_bag,
		"water_bottle", 1, true, 51, 50.0)
	t.check(bool(crime_buy.get("ok", false)), "outlaw may still buy necessary supplies")
	t.eq(int(crime_buy["silver_delta"]), -14,
		"server first discounts earned renown, then applies criminal 25% markup")
	t.eq(criminal_bag.count("silver"), 86, "crime-adjusted price is actually debited")
	t.eq(int(crime_buy["unit_price"]), 14, "UI and server may display exact unit price")
	t.eq(int(Vendor.transact(criminal_bag, "invalid_item", 1, true,
		51, 50.0).get("silver_delta", 0)), 0, "unlisted items never mint payout")

	t.current = "completed real camp contracts grant once-only renown"
	t.eq(server.cmd_contract(player.id, "claim")["reason"], "no_active",
		"claim without an accepted objective is rejected")
	t.check(server.cmd_contract(player.id, "accept")["ok"],
		"server accepts the first genuine survivor camp contract")
	var before_contract: int = player.renown
	t.eq(server.cmd_contract(player.id, "claim")["reason"], "missing_items",
		"failed contract does not generate reputation")
	t.eq(player.renown, before_contract, "no renown for an incomplete mission")
	player.inventory.add("wood_1", 4)
	player.inventory.add("fiber_1", 3)
	t.check(server.cmd_contract(player.id, "claim")["ok"],
		"real delivery completes the mission")
	t.eq(player.renown, before_contract + Reputation.CONTRACT_RENOWN,
		"completed mission awards eight reputation points once")
	t.eq(server.cmd_contract(player.id, "claim")["reason"], "no_active",
		"repeat contract claim is not payable")
	t.eq(player.renown, before_contract + Reputation.CONTRACT_RENOWN,
		"replay cannot duplicate reputation points")

	t.current = "Nakama save migration and corrupted data rejection"
	var saved: Dictionary = server.character_data(player)
	t.eq(saved.get("renown"), player.renown, "character save includes reputation")
	t.check(server.valid_character_data(saved), "new renown save passes server validation")
	var saved_score: int = player.renown
	player.renown = 0
	t.check(server.apply_character(player, saved), "character restore succeeds")
	t.eq(player.renown, saved_score, "reputation survives authentic character load")
	var returning = server.add_player(1443, "Returning Veteran", "account-veteran", saved)
	t.eq(returning.renown, saved_score,
		"fresh authenticated login restores the saved reputation from Nakama")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("renown")
	t.check(server.apply_character(player, legacy), "pre-reputation v1 save still loads")
	t.eq(player.renown, 0, "old characters start at first renown rank")
	var bad: Dictionary = saved.duplicate(true)
	for invalid_score in [NAN, INF, -1, 1.25, "999", Reputation.MAX_RENOWN + 1]:
		bad["renown"] = invalid_score
		t.check(not server.apply_character(player, bad), "corrupt rank fails atomic character restore")
		t.eq(player.renown, 0, "failed restore never changes live renown")
	t.eq(Reputation.rank(500), 3, "rank index never exceeds the last entry")
