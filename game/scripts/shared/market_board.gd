extends RefCounted
## An online-only, server-authoritative listing board. Listings advertise stock;
## nothing is reserved/debited until the buyer and seller complete an atomic exchange.
## This deliberately avoids orphaned escrow while cross-account durable commits
## are not yet provided by the Nakama persistence layer.

const Defs = preload("res://scripts/shared/defs.gd")
const PlayerTrade = preload("res://scripts/shared/player_trade.gd")

const MAX_QUANTITY := 40
const MAX_UNIT_PRICE := 2000
const MAX_LISTINGS := 80
const MAX_PER_SELLER := 4
const LISTING_LIFETIME := 1800.0


static func validate_listing(carried, item_id: String, quantity: int, unit_price: int) -> String:
	if not Defs.is_item(item_id) or item_id == "silver":
		return "invalid_item"
	if quantity < 1 or quantity > MAX_QUANTITY or quantity > Defs.stack_size(item_id):
		return "invalid_quantity"
	if unit_price < 1 or unit_price > MAX_UNIT_PRICE:
		return "invalid_price"
	if carried.count(item_id) < quantity:
		return "missing_items"
	return ""


## Revalidate BOTH backpacks when a listing is purchased, never on the client.
## Item and silver are moved together or no change is committed.
static func purchase(buyer, seller, listing: Dictionary, quantity: int) -> Dictionary:
	if buyer == seller:
		return {"ok": false, "reason": "self_purchase"}
	if quantity < 1 or quantity > int(listing.get("remaining", 0)):
		return {"ok": false, "reason": "invalid_quantity"}
	var item_id: String = str(listing.get("item", ""))
	var price: int = int(listing.get("price", 0))
	if not Defs.is_item(item_id) or item_id == "silver" or price < 1 or price > MAX_UNIT_PRICE:
		return {"ok": false, "reason": "invalid_listing"}
	if quantity > MAX_QUANTITY or quantity > Defs.stack_size(item_id):
		return {"ok": false, "reason": "invalid_quantity"}
	var total: int = price * quantity # Bounded by 80,000 (below silver stack capacity).
	var outcome: Dictionary = PlayerTrade.exchange(seller, buyer, {item_id: quantity}, {"silver": total})
	if not outcome.get("ok", false):
		return outcome
	return {"ok": true, "item": item_id, "quantity": quantity, "total": total}
