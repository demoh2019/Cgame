extends RefCounted
## One atomic bulk deposit of carried raw/refined materials into private bank.
## Existing inventory stacks/slots are the only source of truth.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


static func eligible(item_id: String) -> bool:
	var kind: String = str(Defs.item(item_id).get("kind", ""))
	return kind == "resource" or kind == "material"


## Deterministic partial fill: IDs sorted lexicographically, up to actual
## destination capacity. Stage both containers; neither mutates on failure.
## This never touches food, water, medicine, equipment, tools or silver.
static func deposit(carried, protected_bank) -> Dictionary:
	var ids: Array[String] = []
	for slot in carried.slots:
		if slot.is_empty():
			continue
		var id: String = str(slot["id"])
		if eligible(id) and not ids.has(id):
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		return {"ok": false, "reason": "no_materials"}
	var staged_bag = Inventory.new(carried.slots.size())
	var staged_bank = Inventory.new(protected_bank.slots.size())
	staged_bag.load_dict(carried.to_dict())
	staged_bank.load_dict(protected_bank.to_dict())
	var eligible_count: int = 0
	var total: int = 0
	var moved: Dictionary = {}
	for id in ids:
		var owned: int = staged_bag.count(id)
		eligible_count += owned
		var quantity: int = mini(owned, staged_bank.free_space_for(id))
		if quantity <= 0:
			continue
		if not staged_bag.remove(id, quantity):
			return {"ok": false, "reason": "transaction_failed"}
		if staged_bank.add(id, quantity) != 0:
			return {"ok": false, "reason": "transaction_failed"}
		moved[id] = quantity
		total += quantity
	if total <= 0:
		return {"ok": false, "reason": "no_space"}
	# The sole commit point: both sides already contain the exact receipt.
	carried.load_dict(staged_bag.to_dict())
	protected_bank.load_dict(staged_bank.to_dict())
	return {"ok": true, "total": total, "moved": moved,
		"partial": total < eligible_count, "remaining": eligible_count - total}
