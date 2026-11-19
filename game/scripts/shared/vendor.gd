extends RefCounted
## Authoritative NPC vendor: sell scavenged materials for silver and buy
## basic survival supplies at the existing safe hub workbench.
## A valid trade is simulated on a private inventory copy and committed
## only when both the debit and the credit fully fit.

const Inventory = preload("res://scripts/shared/inventory.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")

const MAX_QUANTITY := 50

const BUY_PRICES := {
	"water_bottle": 12,
	"canned_food": 18,
	"bandage": 16,
}

const SELL_PRICES := {
	"scrap": 3,
	"wood_1": 2,
	"stone_1": 2,
	"ore_1": 3,
	"fiber_1": 2,
	"wood_2": 4,
	"stone_2": 4,
	"ore_2": 6,
	"fiber_2": 4,
	"wood_3": 6,
	"stone_3": 6,
	"ore_3": 9,
	"fiber_3": 6,
	"wood_4": 8,
	"stone_4": 8,
	"ore_4": 12,
	"fiber_4": 8,
	# Fishing is a risk-graded source of silver, but not a buy/sell loop.
	"raw_fish": 4, "raw_fish_2": 8, "raw_fish_3": 14, "raw_fish_4": 22,
	"plank_1": 5, "plank_2": 10, "plank_3": 15, "plank_4": 20,
	"bar_1": 8, "bar_2": 16, "bar_3": 24, "bar_4": 32,
	"cloth_1": 5, "cloth_2": 10, "cloth_3": 15, "cloth_4": 20,
}



## Refining raises the NPC sale value, connecting professions with salvage.
## Prefer a refined item when selling one carried material from a shortcut.
const REFINED_PRIORITY := ["bar_4", "bar_3", "bar_2", "bar_1",
	"plank_4", "plank_3", "plank_2", "plank_1",
	"cloth_4", "cloth_3", "cloth_2", "cloth_1"]


## Prefer the rarest fish first so returning fishers can cash out valuable
## catches without affecting the existing material-salvage shortcut.
const FISH_PRIORITY := ["raw_fish_4", "raw_fish_3", "raw_fish_2", "raw_fish"]


static func first_fish(carried) -> String:
	for item_id in FISH_PRIORITY:
		if carried.count(item_id) > 0:
			return item_id
	return ""


static func first_sellable(carried) -> String:
	for item_id in REFINED_PRIORITY:
		if carried.count(item_id) > 0:
			return item_id
	for item_id in SELL_PRICES:
		if carried.count(item_id) > 0:
			return item_id
	return ""


static func transact(carried, item_id: String, quantity: int, buy: bool,
		renown: int = 0, infamy: float = 0.0) -> Dictionary:
	if quantity < 1 or quantity > MAX_QUANTITY:
		return {"ok": false, "reason": "invalid_quantity"}
	var prices: Dictionary = BUY_PRICES if buy else SELL_PRICES
	var unit_price: int = int(prices.get(item_id, 0))
	if unit_price < 1:
		return {"ok": false, "reason": "not_traded"}
	# Apply server-owned renown discount before outlaw penalty. Prices are
	# per-unit, independent of order splitting, and trades stay atomic.
	if not PvpInfamy.valid(infamy):
		return {"ok": false, "reason": "invalid_infamy"}
	var discounted_unit: int = Reputation.buy_price(unit_price, 1, renown) if buy else unit_price
	unit_price = PvpInfamy.vendor_unit_price(discounted_unit, infamy, buy)
	var total_price: int = unit_price * quantity

	# Never commit a partial payment or a partial item transfer. The same
	# validation works even if the backpack is at its stack/slot limit.
	var trial = Inventory.new(carried.slots.size())
	trial.load_dict(carried.to_dict())
	if buy:
		if not trial.remove("silver", total_price):
			return {"ok": false, "reason": "insufficient_silver"}
		if trial.add(item_id, quantity) != 0:
			return {"ok": false, "reason": "no_space"}
	else:
		if not trial.remove(item_id, quantity):
			return {"ok": false, "reason": "missing_items"}
		if trial.add("silver", total_price) != 0:
			return {"ok": false, "reason": "no_space"}

	carried.load_dict(trial.to_dict())
	# Selling a weapon is currently disallowed, but keep equipment coherent
	# if the price book is expanded to contain other item types.
	carried.unequip_missing()
	return {
		"ok": true, "item": item_id, "quantity": quantity,
		"buy": buy, "silver_delta": -total_price if buy else total_price,
		"unit_price": unit_price,
	}
