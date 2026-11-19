extends RefCounted
## Market board and inventory settlement: stock is never escrowed on posting,
## and buying uses the same all-or-nothing two-inventory rules as direct barter.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _hub(server, player) -> void:
	var at := GameServer.WORKBENCH_POSITION
	player.position = Vector3(at.x, server.world.height_at(at.x, at.y), at.y)


func run(t) -> void:
	t.current = "market validation and all-or-nothing inventory transfer"
	var seller_inv := Inventory.new()
	var buyer_inv := Inventory.new()
	seller_inv.add("wood_1", 10)
	buyer_inv.add("silver", 100)
	t.eq(MarketBoard.validate_listing(seller_inv, "silver", 1, 5), "invalid_item",
		"currency cannot be listed for itself")
	t.eq(MarketBoard.validate_listing(seller_inv, "wood_1", 11, 5), "missing_items",
		"listing must be backed by current inventory")
	t.eq(MarketBoard.validate_listing(seller_inv, "wood_1", 1, 0), "invalid_price",
		"zero price rejected")
	t.eq(MarketBoard.validate_listing(seller_inv, "wood_1", 0, 5), "invalid_quantity",
		"zero quantity rejected")
	var advert := {"item": "wood_1", "remaining": 10, "price": 7}
	var paid := MarketBoard.purchase(buyer_inv, seller_inv, advert, 3)
	t.check(paid["ok"], "atomic purchase succeeds")
	t.eq(seller_inv.count("wood_1"), 7, "seller gives 3 wood")
	t.eq(seller_inv.count("silver"), 21, "seller earns 21 silver")
	t.eq(buyer_inv.count("wood_1"), 3, "buyer gets 3 wood")
	t.eq(buyer_inv.count("silver"), 79, "buyer pays 21 silver")
	t.eq(seller_inv.count("wood_1") + buyer_inv.count("wood_1"), 10, "wood conserved")
	t.eq(seller_inv.count("silver") + buyer_inv.count("silver"), 100, "currency conserved")
	var initial_a: Dictionary = seller_inv.to_dict()
	var initial_b: Dictionary = buyer_inv.to_dict()
	t.eq(MarketBoard.purchase(buyer_inv, seller_inv, advert, 8)["reason"], "missing_items",
		"seller inventory is rechecked when buying")
	t.eq(seller_inv.to_dict(), initial_a, "failed purchase leaves seller unchanged")
	t.eq(buyer_inv.to_dict(), initial_b, "failed purchase leaves buyer unchanged")
	var tiny_buyer := Inventory.new(1)
	tiny_buyer.add("silver", 100)
	initial_b = tiny_buyer.to_dict()
	t.eq(MarketBoard.purchase(tiny_buyer, seller_inv, advert, 1)["reason"], "no_space",
		"no partial transfer when buyer inventory full")
	t.eq(tiny_buyer.to_dict(), initial_b, "no silver deducted on full backpack")
	t.eq(MarketBoard.purchase(seller_inv, seller_inv, advert, 1)["reason"], "self_purchase",
		"self-purchase cannot manufacture currency")

	t.current = "server board, partial fills and replay"
	var server := GameServer.new(WorldGen.new(17), 9)
	var seller = server.add_player(100, "Seller")
	var buyer = server.add_player(200, "Buyer")
	var stranger = server.add_player(300, "Observer")
	_hub(server, seller)
	_hub(server, buyer)
	_hub(server, stranger)
	seller.inventory.add("wood_1", 12)
	buyer.inventory.add("silver", 100)
	var before_list: Dictionary = seller.inventory.to_dict()
	var placed: Dictionary = server.cmd_market_create(100, "wood_1", 10, 5)
	t.check(placed["ok"], "seller advertises 10 wood")
	t.eq(seller.inventory.to_dict(), before_list, "posting is non-escrow: it removes nothing")
	var listing_id: int = int(placed["id"])
	var visible: Dictionary = server.cmd_market_list(200)
	t.eq(visible["orders"].size(), 1, "one listing visible to buyer")
	t.check(not bool(visible["orders"][0]["own"]), "buyer sees another seller")
	t.check(bool(server.cmd_market_list(100)["orders"][0]["own"]), "seller sees own offer")
	t.eq(server.cmd_market_buy(100, listing_id, 1)["reason"], "self_purchase", "no self-dealing")
	var first_sale: Dictionary = server.cmd_market_buy(200, listing_id, 4)
	t.check(first_sale["ok"], "four units purchased")
	t.eq(server.market_orders[listing_id]["remaining"], 6, "six units remain listed")
	t.eq(seller.inventory.count("wood_1"), 8, "seller debited four units")
	t.eq(buyer.inventory.count("wood_1"), 4, "buyer owns four units")
	t.eq(seller.inventory.count("silver"), 20, "seller paid once")
	t.eq(buyer.inventory.count("silver"), 80, "buyer spent twenty")
	t.eq(server.market_sales.size(), 1, "one receipt in bounded session audit")
	t.eq(server.cmd_market_buy(200, listing_id, 7)["reason"], "invalid_quantity",
		"cannot exceed remaining listing amount")
	t.eq(server.cmd_market_cancel(200, listing_id)["reason"], "not_owner",
		"other users cannot cancel seller's order")
	var second_sale: Dictionary = server.cmd_market_buy(200, listing_id, 6)
	t.check(second_sale["ok"], "remaining quantity can be bought")
	t.check(not server.market_orders.has(listing_id), "filled listing is removed")
	t.eq(server.cmd_market_buy(200, listing_id, 1)["reason"], "unknown_listing",
		"replayed purchase cannot double-award items")
	t.eq(seller.inventory.count("silver"), 50, "seller receives 50 silver total")
	t.eq(buyer.inventory.count("wood_1"), 10, "buyer gets 10 wood total")
	t.check(seller.dirty_inventory and buyer.dirty_inventory, "both inventories marked dirty")
	t.check(seller.dirty_character and buyer.dirty_character, "both saves marked dirty")

	t.current = "no trading outside the hub and no stale listings"
	var next: Dictionary = server.cmd_market_create(100, "wood_1", 2, 9)
	var next_id: int = int(next["id"])
	seller.inventory.remove("wood_1", 2)
	t.eq(server.cmd_market_buy(200, next_id, 2)["reason"], "missing_items",
		"advertised goods are not created when seller spends them")
	server._tick_market()
	t.check(not server.market_orders.has(next_id), "unbacked listing is pruned by server tick")
	var remote = server.add_player(400, "Remote")
	remote.inventory.add("wood_1", 2)
	remote.position = Vector3(170.0, server.world.height_at(170.0, 170.0), 170.0)
	t.eq(server.cmd_market_create(400, "wood_1", 1, 9)["reason"], "no_station",
		"remote listing forbidden")
	t.eq(server.cmd_market_buy(400, listing_id, 1)["reason"], "no_station",
		"remote buying forbidden")
	seller.inventory.add("wood_1", 2)
	var cancellation := server.cmd_market_create(100, "wood_1", 1, 9)
	var cancellation_id: int = int(cancellation["id"])
	server.remove_player(100)
	t.check(not server.market_orders.has(cancellation_id), "disconnect cancels online advert")
	t.eq(server.cmd_market_cancel(100, cancellation_id)["reason"], "unknown_listing",
		"cancelled listing cannot be reused")

	t.current = "expiration and death cancel adverts without item losses"
	var safe_seller = server.add_player(501, "Other Seller")
	_hub(server, safe_seller)
	safe_seller.inventory.add("wood_1", 6)
	var expiry := server.cmd_market_create(501, "wood_1", 3, 8)
	var expiry_id: int = int(expiry["id"])
	server.time += MarketBoard.LISTING_LIFETIME + 1.0
	server._tick_market()
	t.check(not server.market_orders.has(expiry_id), "expired advert is removed")
	t.eq(safe_seller.inventory.count("wood_1"), 6, "expiration does not lose any goods")
	var dying := server.cmd_market_create(501, "wood_1", 3, 8)
	safe_seller.survival.hurt(10000.0)
	server._on_player_death(safe_seller, 200)
	t.check(not server.market_orders.has(int(dying["id"])), "death cancels advertised stock")
