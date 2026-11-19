extends RefCounted
## All-or-nothing player-to-player barter. Operates only on server-owned inventories;
## both inventories are copied first, and neither original changes on a rejected trade.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")

const MAX_OFFER_LINES := 4


static func validate_offer(items: Dictionary, inventory) -> String:
	if items.size() > MAX_OFFER_LINES:
		return "too_many_items"
	for item_id in items:
		if not (item_id is String) or not Defs.is_item(item_id):
			return "invalid_item"
		var quantity: Variant = items[item_id]
		if not (quantity is int) or quantity < 1 or quantity > Defs.stack_size(item_id):
			return "invalid_quantity"
		if inventory.count(item_id) < quantity:
			return "missing_items"
	return ""


## Both offers are maps {item_id: amount}, including silver as an ordinary item.
## Does not create or destroy items, including currency, on success or failure.
static func exchange(first, second, first_offer: Dictionary, second_offer: Dictionary) -> Dictionary:
	if first == null or second == null or first == second:
		return {"ok": false, "reason": "invalid_participants"}
	if first_offer.is_empty() and second_offer.is_empty():
		return {"ok": false, "reason": "empty_trade"}
	var reason := validate_offer(first_offer, first)
	if reason != "":
		return {"ok": false, "reason": reason}
	reason = validate_offer(second_offer, second)
	if reason != "":
		return {"ok": false, "reason": reason}
	var working_first = Inventory.new(first.slots.size())
	var working_second = Inventory.new(second.slots.size())
	working_first.load_dict(first.to_dict())
	working_second.load_dict(second.to_dict())
	for item_id in first_offer:
		if not working_first.remove(item_id, int(first_offer[item_id])):
			return {"ok": false, "reason": "missing_items"}
	for item_id in second_offer:
		if not working_second.remove(item_id, int(second_offer[item_id])):
			return {"ok": false, "reason": "missing_items"}
	for item_id in first_offer:
		if working_second.add(item_id, int(first_offer[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	for item_id in second_offer:
		if working_first.add(item_id, int(second_offer[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	working_first.unequip_missing()
	working_second.unequip_missing()
	first.load_dict(working_first.to_dict())
	second.load_dict(working_second.to_dict())
	return {"ok": true, "first_offer": first_offer.duplicate(), "second_offer": second_offer.duplicate()}
