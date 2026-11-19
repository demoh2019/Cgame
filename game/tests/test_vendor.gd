extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "vendor price book"
	t.eq(Vendor.BUY_PRICES["water_bottle"], 12, "water has a fixed purchase cost")
	t.eq(Vendor.SELL_PRICES["scrap"], 3, "scavenged scrap has a fixed sale price")
	for id in Vendor.BUY_PRICES:
		t.check(Defs.is_item(id), "buy item is registered: " + str(id))
		t.check(int(Vendor.BUY_PRICES[id]) > 0, "positive buy price")
	for id in Vendor.SELL_PRICES:
		t.check(Defs.is_item(id), "sale item is registered: " + str(id))
		t.check(int(Vendor.SELL_PRICES[id]) > 0, "positive sale price")
	t.check(not Vendor.BUY_PRICES.has("silver") and not Vendor.SELL_PRICES.has("silver"),
		"cannot trade silver for itself")

	t.current = "atomic sale and purchase"
	var inv := Inventory.new()
	t.eq(Vendor.transact(inv, "water_bottle", 1, true)["reason"], "insufficient_silver",
		"cannot buy with empty wallet")
	t.eq(Vendor.transact(inv, "scrap", 1, false)["reason"], "missing_items",
		"cannot sell goods that are not held")
	inv.add("scrap", 3)
	var sale: Dictionary = Vendor.transact(inv, "scrap", 2, false)
	t.check(sale["ok"], "sells the exact quantity of scrap")
	t.eq(inv.count("scrap"), 1, "debits sold scrap")
	t.eq(inv.count("silver"), 6, "credits 2 x 3 silver")
	t.eq(Vendor.transact(inv, "scrap", 2, false)["reason"], "missing_items",
		"rejects overdraft without a second reward")
	t.eq(inv.count("silver"), 6, "no duplicated silver after failed sale")
	inv.add("silver", 30)
	var buy: Dictionary = Vendor.transact(inv, "water_bottle", 2, true)
	t.check(buy["ok"], "buys exactly two water bottles")
	t.eq(inv.count("water_bottle"), 2, "credits purchased bottles")
	t.eq(inv.count("silver"), 12, "debits exact price of two bottles")
	t.eq(Vendor.transact(inv, "canned_food", 1, true)["reason"],
		"insufficient_silver", "cannot buy overpriced food")
	t.eq(inv.count("silver"), 12, "rejected purchase leaves wallet unchanged")

	t.current = "input and pricing safeguards"
	var old_inventory: Dictionary = inv.to_dict()
	for amount in [0, -1, Vendor.MAX_QUANTITY + 1, 999999]:
		t.eq(Vendor.transact(inv, "water_bottle", amount, true)["reason"],
			"invalid_quantity", "invalid purchase quantity is rejected")
	t.eq(Vendor.transact(inv, "silver", 1, false)["reason"],
		"not_traded", "direct silver sale forbidden")
	t.eq(Vendor.transact(inv, "pistol", 1, false)["reason"],
		"not_traded", "cannot sell weapons without a price listing")
	t.eq(inv.to_dict(), old_inventory, "invalid trades do not mutate backpack")

	t.current = "capacity rollback"
	var full_wallet := Inventory.new(1)
	full_wallet.add("silver", 1000)
	var before: Dictionary = full_wallet.to_dict()
	t.eq(Vendor.transact(full_wallet, "water_bottle", 1, true)["reason"],
		"no_space", "cannot acquire a new stack with no free slot")
	t.eq(full_wallet.to_dict(), before, "failed buy refunds exact silver and keeps stacks")
	var full_goods := Inventory.new(1)
	full_goods.add("wood_1", 10)
	before = full_goods.to_dict()
	t.eq(Vendor.transact(full_goods, "wood_1", 1, false)["reason"],
		"no_space", "cannot sell goods if silver will not fit in any slot")
	t.eq(full_goods.to_dict(), before, "failed sale does not consume wood")

	t.current = "authoritative hub and exploit resistance"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 17)
	var merchant = server.add_player(91, "Merchant")
	merchant.inventory.add("scrap", 2)
	merchant.position = Vector3(120.0, world.height_at(120.0, 120.0), 120.0)
	t.eq(server.cmd_vendor(91, "scrap", 1, false)["reason"], "no_station",
		"remote player cannot trade regardless of client UI")
	t.eq(merchant.inventory.count("silver"), 0, "remote sale grants nothing")
	var hub := GameServer.WORKBENCH_POSITION
	merchant.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	t.check(server.cmd_vendor(91, "scrap", 2, false)["ok"], "server verifies hub position")
	t.eq(merchant.inventory.count("scrap"), 0, "server removes transferred scrap")
	t.eq(merchant.inventory.count("silver"), 6, "server grants exact salvage payment")
	t.eq(server.cmd_vendor(91, "scrap", 2, false)["reason"],
		"missing_items", "replayed sale cannot create additional silver")
	t.eq(merchant.inventory.count("silver"), 6, "no replay payout")
	merchant.inventory.add("silver", 6)
	t.check(server.cmd_vendor(91, "water_bottle", 1, true)["ok"],
		"server trades approved supplies only")
	t.eq(merchant.inventory.count("silver"), 0, "server debits saved wallet")
	t.eq(merchant.inventory.count("water_bottle"), 3,
		"server adds purchased water to two starter bottles")
	t.check(merchant.dirty_inventory and merchant.dirty_character,
		"successful vendor trade marks network and persistent state dirty")
	merchant.survival.hurt(10000.0)
	t.eq(server.cmd_vendor(91, "water_bottle", 1, true)["reason"],
		"dead", "dead players cannot trade")

	t.current = "refined craft material market"
	for item_id in ["plank_1", "plank_4", "bar_2", "cloth_3"]:
		t.eq(int(Vendor.SELL_PRICES[item_id]), int(Defs.item(item_id)["value"]),
			"NPC rewards refined value for " + item_id)
	var smith = server.add_player(92, "Refiner")
	smith.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	smith.inventory.add("plank_1", 1)
	smith.inventory.add("bar_2", 1)
	t.eq(Vendor.first_sellable(smith.inventory), "bar_2", "sell shortcut prioritizes refined metal")
	t.check(server.cmd_vendor(92, "bar_2", 1, false).get("ok", false), "refined bar sold")
	t.eq(smith.inventory.count("silver"), 16, "bar tier-2 payout is 16 silver")
	t.eq(smith.inventory.count("bar_2"), 0, "refined input debited exactly")
	t.eq(Vendor.first_sellable(smith.inventory), "plank_1", "falls back to carried plank")
	t.check(server.cmd_vendor(92, "plank_1", 1, false).get("ok", false), "refined plank sold")
	t.eq(smith.inventory.count("silver"), 21, "refined profession earnings add up")
	t.eq(Vendor.first_sellable(smith.inventory), "", "no phantom materials")
	t.eq(server.cmd_vendor(92, "bar_2", 1, false).get("reason"), "missing_items",
		"repeat trade cannot mint silver")
