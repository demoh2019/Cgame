extends RefCounted
## Shared, strict, side-effect-free validation of persistent character containers.
## Treat Nakama storage as persisted input, not an implicit authority to mint items.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")

const MAX_COUNTER := 2147483647


static func finite_number(value: Variant, lower: float, upper: float) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number >= lower and number <= upper


static func valid_counter(value: Variant) -> bool:
	return finite_number(value, 0.0, float(MAX_COUNTER)) and float(value) == floor(float(value))


## Returns {"inventory": Inventory} or {}, never partial data.
## allow_equipment=false is used for settlement bank stacks (not wearable slots).
static func parse_inventory(raw: Variant, expected_slots: int, allow_equipment: bool = true) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var raw_slots: Variant = raw.get("slots")
	if not (raw_slots is Array) or raw_slots.size() != expected_slots:
		return {}
	var clean_slots: Array = []
	for slot in raw_slots:
		if not (slot is Dictionary):
			return {}
		if slot.is_empty():
			clean_slots.append({})
			continue
		var item_id: Variant = slot.get("id")
		var amount: Variant = slot.get("count")
		if not (item_id is String) or not Defs.is_item(item_id):
			return {}
		if not finite_number(amount, 1.0, float(Defs.stack_size(item_id))):
			return {}
		if float(amount) != floor(float(amount)):
			return {}
		clean_slots.append({"id": item_id, "count": int(amount)})
	var inventory = Inventory.new(expected_slots)
	inventory.slots = clean_slots

	for slot_name in ["weapon", "armor"]:
		var equipped: Variant = raw.get(slot_name, "")
		if not (equipped is String):
			return {}
		if equipped.is_empty():
			continue
		if not allow_equipment or inventory.count(equipped) < 1:
			return {}
		if str(Defs.item(equipped).get("kind", "")) != slot_name:
			return {}
		if slot_name == "weapon":
			inventory.weapon = equipped
		else:
			inventory.armor = equipped
	return {"inventory": inventory}
