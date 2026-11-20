extends RefCounted
## Server-owned consumable loadouts: withdrawals only, never purchased or
## generated items. Presets are immutable and each is bounded to item stacks.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")

const ORDER := ["scout", "archer", "gunner", "medic"]
const TARGETS := {
	"scout": {"water_bottle": 3, "canned_food": 3, "bandage": 4,
		"field_antiseptic": 1, "field_splint": 1},
	"archer": {"water_bottle": 2, "canned_food": 2, "bandage": 3,
		"arrow": 48, "herbal_poultice": 2},
	"gunner": {"water_bottle": 2, "canned_food": 2, "bandage": 3,
		"ammo_9mm": 48, "field_antiseptic": 1},
	"medic": {"water_bottle": 3, "canned_food": 2, "bandage": 6,
		"field_antiseptic": 3, "antibiotics": 2, "field_triage_pack": 1},
}
const NAMES := {"scout": "Scout", "archer": "Archer", "gunner": "Gunner", "medic": "Medic"}


static func title(preset_id: String) -> String:
	return str(NAMES.get(preset_id, preset_id))


static func valid_preset(preset_id: String) -> bool:
	return TARGETS.has(preset_id)


## Stage two inventory snapshots and commit only after every proposed
## transfer succeeds. Count already carried supplies against target, leaving
## extra carried items intact. Missing bank stock and full slots are skipped.
static func restock(carried, protected_bank, preset_id: String) -> Dictionary:
	if not valid_preset(preset_id):
		return {"ok": false, "reason": "unknown_preset"}
	var desired: Dictionary = TARGETS[preset_id]
	var bag = Inventory.new(carried.slots.size())
	var bank = Inventory.new(protected_bank.slots.size())
	bag.load_dict(carried.to_dict())
	bank.load_dict(protected_bank.to_dict())
	var moved: Dictionary = {}
	var total: int = 0
	var missing_before: int = 0
	var available: int = 0
	for item_id in desired:
		var id: String = str(item_id)
		var target: int = int(desired[item_id])
		if not Defs.is_item(id) or target < 1 or target > Defs.stack_size(id):
			return {"ok": false, "reason": "invalid_preset"}
		var missing: int = maxi(0, target - bag.count(id))
		missing_before += missing
		available += mini(missing, bank.count(id))
		var quantity: int = mini(mini(missing, bank.count(id)), bag.free_space_for(id))
		if quantity < 1:
			continue
		if not bank.remove(id, quantity):
			return {"ok": false, "reason": "transaction_failed"}
		if bag.add(id, quantity) != 0:
			return {"ok": false, "reason": "transaction_failed"}
		moved[id] = quantity
		total += quantity
	if total == 0:
		if missing_before == 0:
			return {"ok": false, "reason": "already_supplied"}
		return {"ok": false, "reason": "no_stock" if available == 0 else "no_space"}
	# Exactly one commit point after all capacity checks and transfers.
	carried.load_dict(bag.to_dict())
	protected_bank.load_dict(bank.to_dict())
	return {"ok": true, "preset": preset_id, "total": total, "moved": moved,
		"missing": missing_before - total, "partial": total < missing_before}
