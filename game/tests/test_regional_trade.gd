extends RefCounted
## Authenticated village trade demand without buy/sell arbitrage or fake prices.
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _stations(world) -> Array:
	var found: Array = []
	for rx in range(-6, 7):
		for rz in range(-6, 7):
			for site in world.poi.sites_in_region(rx, rz):
				if bool(site["station"]):
					found.append(site)
	return found


func _item_for(category: String) -> String:
	return "raw_fish" if category == "fish" else category + "_1"


func run(t) -> void:
	t.current = "seeded village demand and commodity restrictions"
	var world := WorldGen.new(1337)
	var sites: Array = _stations(world)
	t.check(sites.size() >= 3, "world contains several NPC trader settlements")
	if sites.size() < 3:
		return
	var offers: Dictionary = {}
	for site in sites:
		var offer: Dictionary = RegionalTrade.offer_for_site(site)
		t.check(not offer.is_empty(), "every settlement has a bounded demand")
		t.check(int(offer["premium_percent"]) >= 35 and \
				int(offer["premium_percent"]) <= 75, "bounded premium")
		offers[str(offer["category"])] = true
	t.check(offers.size() >= 2, "different settlements prefer different commodities")
	var source: Dictionary = sites[0]
	var demand: Dictionary = RegionalTrade.offer_for_site(source)
	var item_id: String = _item_for(str(demand["category"]))
	var base: int = int(Vendor.SELL_PRICES[item_id])
	t.check(RegionalTrade.sell_price(item_id, demand) > base,
		"matching raw resource receives a real premium")
	t.eq(RegionalTrade.sell_price("bar_1", demand), Vendor.SELL_PRICES["bar_1"],
		"processed bars are excluded from premium")
	t.eq(RegionalTrade.sell_price("silver", demand), 0,
		"currency is never tradable for itself")
	t.eq(RegionalTrade.sell_price(item_id, {}), base,
		"normal hub keeps normal price")
	t.eq(RegionalTrade.offer_for_site(source),
		RegionalTrade.offer_for_site(source.duplicate(true)),
		"identical seed gives reproducible price, no random rerolls")
	t.check(RegionalTrade.offer_for_site({"station": false}).is_empty(),
		"sites with no trader cannot issue quotes")

	t.current = "server validates actual station distance"
	var station := Vector3(float(source["station_x"]),
		world.height_at(float(source["station_x"]), float(source["station_z"])),
		float(source["station_z"]))
	var offer_here: Dictionary = RegionalTrade.local_offer(world, station)
	t.eq(offer_here, demand, "server finds verified merchant in world")
	t.check(RegionalTrade.local_offer(world, station + Vector3(40, 0, 0)).is_empty(),
		"outside station range cannot access premium")
	t.check(RegionalTrade.local_offer(world, Vector3.INF).is_empty(),
		"invalid coordinates never generate a quote")
	t.check(RegionalTrade.local_offer(world, Vector3(0, world.height_at(0, 0), 0)).is_empty(),
		"the starting hub is neutral")
	var public: Dictionary = RegionalTrade.public_offer(world, station)
	t.check(public.has("name") and public.has("premium_percent"),
		"client can display verified settlement name and demand")
	t.check(not public.has("seed") and not public.has("station_x"),
		"public quote hides seeded lookup implementation")

	t.current = "real NPC sale, exact money debit and replay protection"
	var sim := GameServer.new(world, 1337)
	var player = sim.add_player(255, "Merchant")
	player.position = station
	player.inventory.add(item_id, 3)
	var before: int = player.inventory.count("silver")
	var unit: int = RegionalTrade.sell_price(item_id, demand)
	var result: Dictionary = sim.cmd_vendor(255, item_id, 2, false)
	t.check(bool(result.get("ok", false)), "regional sale succeeds beside actual trader")
	t.eq(int(result.get("unit_price", 0)), unit,
		"authoritative merchant pays exact quoted amount")
	t.eq(int(result.get("silver_delta", 0)), 2 * unit,
		"two resources produce correct bounded currency")
	t.eq(player.inventory.count(item_id), 1, "sale removes exactly two resources")
	t.eq(player.inventory.count("silver"), before + 2 * unit,
		"sale commits the credited silver")
	t.eq(result.get("settlement"), demand["name"],
		"receipt names actual destination")
	var sold_again: Dictionary = sim.cmd_vendor(255, item_id, 2, false)
	t.eq(sold_again.get("reason"), "missing_items",
		"replaying a sale with insufficient goods cannot mint currency")
	t.eq(player.inventory.count("silver"), before + 2 * unit,
		"second failed sale leaves wallet unchanged")
	t.check(player.dirty_inventory and player.dirty_character,
		"new income is persisted and replicated")

	t.current = "no forged buy quotation, overflow or risk-free infinite loop"
	var inv := Inventory.new()
	inv.add("silver", 100)
	t.eq(Vendor.transact(inv, "water_bottle", 1, true, 0, 0.0, 999999)
		.get("reason"), "invalid_quote", "cannot submit a quote for purchases")
	t.eq(Vendor.transact(inv, item_id, 1, false, 0, 0.0, 999999)
		.get("reason"), "invalid_quote", "unbounded sale prices are rejected")
	t.eq(Vendor.transact(inv, item_id, 1, false, 0, 0.0, base - 1)
		.get("reason"), "invalid_quote", "cannot set a discount quote")
	t.eq(inv.count("silver"), 100, "invalid prices never modify silver")
	var payout: int = RegionalTrade.sell_price(item_id, {
		"category": demand["category"], "premium_percent": 1000000})
	t.check(payout <= ceili(float(base) * 1.75),
		"even corrupt quote payload cannot exceed 75 percent")
	var buy: Dictionary = sim.cmd_vendor(255, item_id, 1, true)
	t.eq(buy.get("reason"), "not_traded",
		"merchants never sell regional raw goods back to players")
	var snapshot: Dictionary = sim.snapshot_for(255)["you"]
	t.eq(snapshot.get("regional_trade"), public,
		"snapshot contains only the current server-verified market")
	player.position = Vector3(0, world.height_at(0, 0), 0)
	t.check(sim.snapshot_for(255)["you"].get("regional_trade", {}).is_empty(),
		"leaving the village clears its demand quote")
