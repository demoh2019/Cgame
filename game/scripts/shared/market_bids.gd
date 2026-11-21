extends RefCounted
## Albion Online-style buy orders. A buyer escrows silver for "N x item at price P";
## any seller at the hub can instantly sell into the highest order. Goods go to the
## buyer's market deliveries (collected at the hub), the seller is paid at once minus
## the usual sales tax. Cancelled or expired orders refund the unspent silver.

const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Defs = preload("res://scripts/shared/defs.gd")

const MAX_BIDS := 80
const MAX_PER_BUYER := 4
const BID_LIFETIME := 7.0 * 86400.0


static func validate_bid(silver_carried: int, item_id: String, quantity: int, unit_price: int) -> String:
	if not Defs.is_item(item_id) or item_id == "silver":
		return "invalid_item"
	if quantity < 1 or quantity > MarketBoard.MAX_QUANTITY:
		return "invalid_quantity"
	if unit_price < 1 or unit_price > MarketBoard.MAX_UNIT_PRICE:
		return "invalid_price"
	if silver_carried < quantity * unit_price:
		return "need_silver"
	return ""


## Highest price first, then oldest (lower id) first.
static func best_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a["price"]) != int(b["price"]):
		return int(a["price"]) > int(b["price"])
	return int(a["id"]) < int(b["id"])


## Units of `item_id` a seller can hand over (carried, minus what is equipped).
static func sellable(inventory, item_id: String) -> int:
	var have: int = inventory.count(item_id)
	if inventory.is_equipped(item_id):
		have -= 1
	return maxi(0, have)
