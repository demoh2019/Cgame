extends RefCounted
## An online-only, server-authoritative listing board. Listings advertise stock;
## nothing is reserved/debited until the buyer and seller complete an atomic exchange.
## This deliberately avoids orphaned escrow while cross-account durable commits
## are not yet provided by the Nakama persistence layer.
##
## Market sales burn a bounded seller-side commission as a silver sink.
## Direct player barter remains untaxed.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")

const MAX_QUANTITY := 40
const MAX_UNIT_PRICE := 2000
const MAX_LISTINGS := 80
const MAX_PER_SELLER := 4
const LISTING_LIFETIME := 1800.0
const SALE_TAX_PERCENT := 3


static func sale_tax(total: int) -> int:
	# Seller always earns at least one silver, even for a 1-silver listing.
	if total <= 1:
		return 0
	return mini(ceili(float(total) * float(SALE_TAX_PERCENT) / 100.0), total - 1)


## Listings promise real carried stock without removing it. Multiple adverts
## from the same seller cannot collectively promise more than their backpack
## contains, while separate sellers and items remain independent.
static func listed_quantity(orders: Dictionary, seller_id: int, item_id: String) -> int:
	var claimed := 0
	for order in orders.values():
		if int(order.get("seller", -1)) == seller_id and str(order.get("item", "")) == item_id:
			claimed += maxi(0, int(order.get("remaining", 0)))
	return claimed


static func unlisted_stock(carried, orders: Dictionary, seller_id: int, item_id: String) -> int:
	return maxi(0, carried.count(item_id) - listed_quantity(orders, seller_id, item_id))


## Browse by item then cheapest unit price, with stable older-listing precedence.
## Sorting is purely presentational; purchase still uses the original listing ID.
static func cheaper_first(a: Dictionary, b: Dictionary) -> bool:
	var left: String = str(a.get("item", ""))
	var right: String = str(b.get("item", ""))
	if left != right:
		return left.casecmp_to(right) < 0
	var a_price: int = int(a.get("price", 0))
	var b_price: int = int(b.get("price", 0))
	if a_price != b_price:
		return a_price < b_price
	return int(a.get("id", 0)) < int(b.get("id", 0))


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


## Revalidate BOTH backpacks at settlement. All item and silver transfers,
## including the tax burn, happen on staged inventories and only commit together.
## Unlike a gross-first barter transfer this also handles the silver-stack edge:
## a seller may have room for net proceeds but not for the untaxed gross total.
static func purchase(buyer, seller, listing: Dictionary, quantity: int) -> Dictionary:
	if buyer == null or seller == null:
		return {"ok": false, "reason": "invalid_participants"}
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
	var tax: int = sale_tax(total)
	var seller_net: int = total - tax
	var staged_seller = Inventory.new(seller.slots.size())
	var staged_buyer = Inventory.new(buyer.slots.size())
	staged_seller.load_dict(seller.to_dict())
	staged_buyer.load_dict(buyer.to_dict())
	if not staged_seller.remove(item_id, quantity):
		return {"ok": false, "reason": "missing_items"}
	if not staged_buyer.remove("silver", total):
		return {"ok": false, "reason": "missing_items"}
	if staged_buyer.add(item_id, quantity) != 0 or staged_seller.add("silver", seller_net) != 0:
		return {"ok": false, "reason": "no_space"}
	staged_seller.unequip_missing()
	staged_buyer.unequip_missing()
	seller.load_dict(staged_seller.to_dict())
	buyer.load_dict(staged_buyer.to_dict())
	return {"ok": true, "item": item_id, "quantity": quantity,
		"total": total, "tax": tax, "seller_net": seller_net}
