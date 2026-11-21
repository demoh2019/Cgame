extends RefCounted
## Albion-style buy orders: escrowed silver, instant fills at the hub, refunds, persistence.

const Inventory = preload("res://scripts/shared/inventory.gd")
const MarketBids = preload("res://scripts/shared/market_bids.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")


func run(t) -> void:
	t.current = "bid validation"
	t.eq(MarketBids.validate_bid(100, "wood_1", 10, 5), "", "affordable bid is valid")
	t.eq(MarketBids.validate_bid(10, "wood_1", 10, 5), "need_silver", "bids must be fully funded")
	t.eq(MarketBids.validate_bid(100, "silver", 1, 1), "invalid_item", "no silver-for-silver")
	t.check(MarketBids.best_first({"price": 9, "id": 2}, {"price": 5, "id": 1}), "highest price first")

	var world = WorldGen.new(1357)
	var server := GameServer.new(world, 21)
	var hub := Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	var buyer = server.add_player(1001, "Buyer")
	var seller = server.add_player(1002, "Seller")
	for p in [buyer, seller]:
		p.inventory = Inventory.new()
		p.position = hub
	buyer.user_id = "acct-buyer"
	seller.user_id = "acct-seller"
	buyer.inventory.add("silver", 100)
	seller.inventory.add("wood_1", 30)

	t.current = "placing a buy order escrows silver"
	var placed: Dictionary = server.cmd_market_bid(1001, "wood_1", 10, 5)
	t.check(bool(placed.get("ok", false)), "buy order placed at the hub")
	t.eq(buyer.inventory.count("silver"), 50, "50 silver held in escrow")
	var bid_id: int = int(placed["id"])
	t.eq((server.cmd_market_list(1002)["bids"] as Array).size(), 1, "sellers see the order")

	t.current = "selling into the order"
	t.eq(server.cmd_market_fill(1001, bid_id, 1).get("reason"), "self_trade", "no filling your own order")
	var filled: Dictionary = server.cmd_market_fill(1002, bid_id, 4)
	t.check(bool(filled.get("ok", false)), "seller fills part of the order")
	t.eq(seller.inventory.count("wood_1"), 26, "goods leave the seller")
	t.eq(seller.inventory.count("silver"), 20 - MarketBoard.sale_tax(20), "seller is paid at once, minus tax")
	server.cmd_market_list(1001)
	t.eq(buyer.inventory.count("wood_1"), 4, "buyer collects the goods at the hub")

	t.current = "persistence and refunds"
	var snapshot: Dictionary = WorldPersistence.capture(server)
	t.eq((snapshot["market"]["bids"] as Array).size(), 1, "open orders are saved with the world")
	t.check(bool(server.cmd_market_cancel_bid(1001, bid_id).get("ok", false)), "owner cancels the rest")
	server.cmd_market_list(1001)
	t.eq(buyer.inventory.count("silver"), 80, "unspent escrow (6 x 5) comes back")
	t.eq(server.market_bids.size(), 0, "order is gone")
