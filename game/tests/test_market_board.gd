extends RefCounted
## Market board and inventory settlement: posting escrows the stock with the market,
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
	t.eq(seller_inv.count("silver"), 20, "seller receives 20 after 1 silver tax")
	t.eq(buyer_inv.count("wood_1"), 3, "buyer gets 3 wood")
	t.eq(buyer_inv.count("silver"), 79, "buyer pays 21 silver")
	t.eq(seller_inv.count("wood_1") + buyer_inv.count("wood_1"), 10, "wood conserved")
	t.eq(seller_inv.count("silver") + buyer_inv.count("silver"), 99,
		"one market-tax silver is removed from circulation")
	t.eq(paid["total"], 21, "buyer pays advertised gross amount")
	t.eq(paid["tax"], 1, "commission rounds up to one silver")
	t.eq(paid["seller_net"], 20, "seller receives gross less commission")
	t.eq(MarketBoard.sale_tax(1), 0, "a one-silver trade still pays its seller")
	t.eq(MarketBoard.sale_tax(2), 1, "minimum seller income is one silver")
	t.eq(MarketBoard.sale_tax(33), 1, "tax rounds upward at three percent")
	t.eq(MarketBoard.sale_tax(34), 2, "tax jumps only at correct boundary")
	t.eq(MarketBoard.sale_tax(100), 3, "full percentage applied to larger trades")
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

	t.current = "seller silver capacity and tax transaction rollback"
	var full_seller := Inventory.new(2)
	var modest_buyer := Inventory.new(2)
	full_seller.add("wood_1", 1)
	full_seller.add("silver", 99999)
	modest_buyer.add("silver", 2)
	var low_order: Dictionary = {"item": "wood_1", "price": 2, "remaining": 1}
	t.check(MarketBoard.purchase(modest_buyer, full_seller, low_order, 1)["ok"],
		"net settlement fits even when gross sale would overflow the seller's silver stack")
	t.eq(full_seller.count("silver"), 100000, "seller receives net 1 silver at the cap")
	t.eq(modest_buyer.count("silver"), 0, "buyer still pays full gross 2 silver")
	t.eq(modest_buyer.count("wood_1"), 1, "buyer receives item exactly once")
	# Two wood: selling one keeps the wood slot occupied, so the net proceeds really have nowhere to go (with a single
	# wood the sale frees its slot and the silver legitimately fits there as a new stack).
	full_seller.add("wood_1", 2)
	modest_buyer.add("silver", 3)
	var seller_before: Dictionary = full_seller.to_dict()
	var buyer_before: Dictionary = modest_buyer.to_dict()
	low_order["price"] = 3
	t.eq(MarketBoard.purchase(modest_buyer, full_seller, low_order, 1).get("reason", ""),
		"no_space", "sale rejected when net proceeds would overflow seller's stack")
	t.eq(full_seller.to_dict(), seller_before, "seller is unchanged after failed net settlement")
	t.eq(modest_buyer.to_dict(), buyer_before, "buyer is unchanged after failed net settlement")

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
	t.eq(seller.inventory.count("wood_1"), 2, "posting escrows the listed goods (12 - 10)")
	var listing_id: int = int(placed["id"])
	var visible: Dictionary = server.cmd_market_list(200)
	t.eq(visible["orders"].size(), 1, "one listing visible to buyer")
	t.check(not bool(visible["orders"][0]["own"]), "buyer sees another seller")
	t.check(bool(server.cmd_market_list(100)["orders"][0]["own"]), "seller sees own offer")
	t.eq(server.cmd_market_buy(100, listing_id, 1, 1)["reason"], "self_purchase", "no self-dealing")
	var first_sale: Dictionary = server.cmd_market_buy(200, listing_id, 4, 1)
	t.check(first_sale["ok"], "four units purchased")
	t.eq(server.cmd_market_buy(200, listing_id, 4, 1), first_sale,
		"same request ID returns cached receipt without buying again")
	t.eq(server.cmd_market_buy(200, listing_id, 5, 1)["reason"], "request_conflict",
		"reused ID with different quantity cannot be executed")
	t.eq(server.cmd_market_buy(200, listing_id, 4, 0)["reason"], "invalid_request_id",
		"zero request ID rejected")
	t.eq(server.cmd_market_buy(200, listing_id, 4, -1)["reason"], "invalid_request_id",
		"negative request ID rejected")
	t.eq(server.cmd_market_buy(200, listing_id, 4, GameServer.MARKET_MAX_REQUEST_ID + 1)["reason"],
		"invalid_request_id", "oversized request ID rejected")
	t.eq(server.market_orders[listing_id]["remaining"], 6, "six units remain listed")
	t.eq(seller.inventory.count("wood_1"), 2, "escrowed goods were already taken; the sale debits nothing more")
	t.eq(buyer.inventory.count("wood_1"), 4, "buyer owns four units")
	t.eq(seller.inventory.count("silver"), 19, "seller paid once after tax")
	t.eq(buyer.inventory.count("silver"), 80, "buyer spent twenty")
	t.eq(server.market_sales.size(), 1, "one receipt in bounded session audit")
	t.eq(first_sale["total"], 20, "buyer sees the agreed gross total")
	t.eq(first_sale["tax"], 1, "receipt discloses charged seller commission")
	t.eq(first_sale["seller_net"], 19, "receipt discloses net seller payout")
	t.eq(server.market_sales[0]["tax"], 1, "market session audit records tax once")
	t.eq(server.market_sales[0]["seller_net"], 19, "audit records net payout")
	t.eq(server.cmd_market_buy(200, listing_id, 7, 2)["reason"], "invalid_quantity",
		"cannot exceed remaining listing amount")
	t.eq(server.cmd_market_buy(200, listing_id, 7, 2)["reason"], "invalid_quantity",
		"a failed request is also idempotent")
	t.eq(server.cmd_market_cancel(200, listing_id)["reason"], "not_owner",
		"other users cannot cancel seller's order")
	var second_sale: Dictionary = server.cmd_market_buy(200, listing_id, 6, 3)
	t.check(second_sale["ok"], "remaining quantity can be bought")
	t.eq(server.cmd_market_buy(200, listing_id, 4, 1)["reason"], "stale_request",
		"old request cannot execute again after another purchase")
	t.check(not server.market_orders.has(listing_id), "filled listing is removed")
	t.eq(server.cmd_market_buy(200, listing_id, 1, 4)["reason"], "unknown_listing",
		"replayed purchase cannot double-award items")
	t.eq(seller.inventory.count("silver"), 48, "seller receives 48 after two market sales taxes")
	t.eq(buyer.inventory.count("wood_1"), 10, "buyer gets 10 wood total")
	t.eq(server.market_sales[1]["tax"], 1, "second partial fill is independently taxed")
	t.eq(server.market_sales[1]["seller_net"], 29, "second sale pays 29 silver net")
	t.eq(seller.inventory.count("silver") + buyer.inventory.count("silver"), 98,
		"exactly 2 silver was burned across both market fills")
	t.check(seller.dirty_inventory and buyer.dirty_inventory, "both inventories marked dirty")
	t.check(seller.dirty_character and buyer.dirty_character, "both saves marked dirty")

	t.current = "escrowed listings survive the seller (offline sales, hub payouts)"
	var next: Dictionary = server.cmd_market_create(100, "wood_1", 2, 9)
	var next_id: int = int(next["id"])
	t.check(bool(next.get("ok", false)), "second listing escrows two more wood")
	var remote = server.add_player(400, "Remote")
	remote.inventory.add("wood_1", 2)
	remote.position = Vector3(170.0, server.world.height_at(170.0, 170.0), 170.0)
	t.eq(server.cmd_market_create(400, "wood_1", 1, 9)["reason"], "no_station",
		"remote listing forbidden")
	t.eq(server.cmd_market_buy(400, next_id, 1, 1)["reason"], "no_station",
		"remote buying forbidden")
	var seller_account: String = server._market_account(seller)
	var silver_before_logout: int = seller.inventory.count("silver")
	server.remove_player(100)
	t.check(not server.market_buy_requests.has(100), "disconnect clears request state for recycled peer ids")
	t.check(server.market_orders.has(next_id), "escrowed listing stays up while the seller is offline")
	var offline_sale: Dictionary = server.cmd_market_buy(200, next_id, 2, 5)
	t.check(bool(offline_sale.get("ok", false)), "goods sell while the seller is away")
	t.check(int(server.market_payouts.get(seller_account, 0)) > 0, "proceeds wait for the seller at the hub")
	t.eq(silver_before_logout, 48, "earlier online sales were already paid")

	t.current = "expiration returns goods; death does not cancel escrow"
	var safe_seller = server.add_player(501, "Other Seller")
	_hub(server, safe_seller)
	safe_seller.inventory.add("wood_1", 6)
	var expiry := server.cmd_market_create(501, "wood_1", 3, 8)
	var expiry_id: int = int(expiry["id"])
	t.eq(safe_seller.inventory.count("wood_1"), 3, "three wood held in escrow")
	server.time += MarketBoard.LISTING_LIFETIME + 1.0
	server._tick_market()
	t.check(not server.market_orders.has(expiry_id), "expired listing is removed")
	server.cmd_market_list(501)
	t.eq(safe_seller.inventory.count("wood_1"), 6, "unsold goods come back when collected at the hub")
	var dying := server.cmd_market_create(501, "wood_1", 3, 8)
	safe_seller.survival.hurt(10000.0)
	server._on_player_death(safe_seller, 200)
	t.check(server.market_orders.has(int(dying["id"])), "death does not cancel escrowed stock (it is no longer carried)")

	t.current = "non-escrow listing budgets and lowest-price-first browsing"
	var order_book: Dictionary = {
		10: {"seller": 1, "item": "wood_1", "remaining": 7},
		11: {"seller": 1, "item": "wood_1", "remaining": 3},
		12: {"seller": 2, "item": "wood_1", "remaining": 4},
		13: {"seller": 1, "item": "stone_1", "remaining": 2},
	}
	var sample_pack := Inventory.new()
	sample_pack.add("wood_1", 11)
	t.eq(MarketBoard.listed_quantity(order_book, 1, "wood_1"), 10,
		"same seller's live order quantities are added across listings")
	t.eq(MarketBoard.unlisted_stock(sample_pack, order_book, 1, "wood_1"), 1,
		"only remaining carried goods are available for a new listing")
	t.eq(MarketBoard.listed_quantity(order_book, 2, "wood_1"), 4,
		"another seller's advertised stock stays independent")
	t.eq(MarketBoard.listed_quantity(order_book, 1, "stone_1"), 2,
		"different resources do not compete for listing capacity")
	t.eq(MarketBoard.unlisted_stock(sample_pack, order_book, 1, "stone_1"), 0,
		"advertised quantity never yields negative available inventory")
	t.check(MarketBoard.cheaper_first(
		{"item": "wood_1", "price": 5, "id": 2},
		{"item": "wood_1", "price": 7, "id": 3}), "cheaper wood comes first")
	t.check(MarketBoard.cheaper_first(
		{"item": "wood_1", "price": 5, "id": 2},
		{"item": "wood_1", "price": 5, "id": 3}), "same-price orders keep older ID first")
	t.check(MarketBoard.cheaper_first(
		{"item": "stone_1", "price": 99, "id": 7},
		{"item": "wood_1", "price": 1, "id": 1}), "market groups by item before price")

	t.current = "escrow prevents double-listing; partial fills and cheapest-first browsing"
	var depth := GameServer.new(WorldGen.new(39), 39)
	var maker = depth.add_player(701, "Maker")
	var rival = depth.add_player(702, "Rival")
	var taker = depth.add_player(703, "Taker")
	_hub(depth, maker)
	_hub(depth, rival)
	_hub(depth, taker)
	maker.inventory.add("wood_1", 10)
	rival.inventory.add("wood_1", 3)
	taker.inventory.add("silver", 1000)
	var expensive: Dictionary = depth.cmd_market_create(701, "wood_1", 7, 20)
	t.check(bool(expensive.get("ok", false)), "first seven-unit listing is posted")
	t.eq(maker.inventory.count("wood_1"), 3, "the seven listed units move into escrow")
	var old_id: int = int(expensive.get("id", -1))
	var rejected: Dictionary = depth.cmd_market_create(701, "wood_1", 4, 15)
	t.check(not bool(rejected.get("ok", false)), "cannot list four more while carrying three")
	t.eq(depth.market_orders.size(), 1, "rejected listing is never published")
	var cheap: Dictionary = depth.cmd_market_create(701, "wood_1", 3, 15)
	var bargain: Dictionary = depth.cmd_market_create(702, "wood_1", 3, 5)
	t.check(cheap.get("ok", false) and bargain.get("ok", false),
		"remaining stock and another seller may both be listed")
	t.eq(maker.inventory.count("wood_1"), 0, "all of the maker's wood is now in escrow")
	var browsing: Array = depth.cmd_market_list(703)["orders"]
	t.eq(browsing.size(), 3, "all three listings are visible")
	if browsing.size() == 3:
		t.eq([browsing[0]["id"], browsing[1]["id"], browsing[2]["id"]],
			[bargain["id"], cheap["id"], expensive["id"]],
			"same-item offers sort by lowest price, not by creation order")
	var sale: Dictionary = depth.cmd_market_buy(703, old_id, 4, 1)
	t.check(sale.get("ok", false), "real partial fill settles normally")
	t.eq(taker.inventory.count("wood_1"), 4, "four listed items are delivered")
	t.eq(int(depth.market_orders[old_id]["remaining"]), 3, "the listing keeps the other three")
	t.eq(depth.cmd_market_create(701, "wood_1", 1, 10).get("ok", false), false,
		"nothing left to list once everything is escrowed")
	t.eq(depth.cmd_market_buy(703, old_id, 4, 1), sale,
		"replayed purchase returns the original result")
	t.eq(rival.inventory.count("wood_1"), 0, "the rival's listed wood is escrowed too")
