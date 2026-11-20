extends RefCounted
## Atomic, private party supply handoff at one server-owned live campfire.
## Neither the fire ID, item IDs nor quantities are client-authored.

const Inventory = preload("res://scripts/shared/inventory.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const PartyFeast = preload("res://scripts/shared/party_feast.gd")

const PACKAGES := {
	"food": {"canned_food": 1},
	"water": {"water_bottle": 1},
	"kit": {"canned_food": 1, "water_bottle": 1},
	"stew": {"camp_fish_stew": 1},
}


static func package_items(kind: String) -> Dictionary:
	return (PACKAGES[kind] as Dictionary).duplicate() if PACKAGES.has(kind) else {}


## Both survivors must be close and within the SAME burning fire's radius.
static func shared_fire(campfires: Dictionary, source: Vector3,
		target: Vector3, now: float) -> bool:
	if not PartyAid.can_reach(source, target) or not is_finite(now):
		return false
	for value in campfires.values():
		if not (value is Dictionary):
			continue
		var fire: Dictionary = value
		if PartyFeast.near_fire(fire, source, now) and PartyFeast.near_fire(fire, target, now):
			return true
	return false


## Stage both backpacks: the donor never loses items if the recipient is full.
static func transfer(source, target, kind: String) -> String:
	if source == null or target == null or source == target:
		return "invalid_inventory"
	var items: Dictionary = package_items(kind)
	if items.is_empty():
		return "invalid_package"
	if not source.has_all(items):
		return "missing_supplies"
	var donor = Inventory.new(source.slots.size())
	var receiver = Inventory.new(target.slots.size())
	donor.load_dict(source.to_dict())
	receiver.load_dict(target.to_dict())
	for item_id in items:
		var amount: int = int(items[item_id])
		if not donor.remove(str(item_id), amount):
			return "missing_supplies"
		if receiver.add(str(item_id), amount) != 0:
			return "no_space"
	source.load_dict(donor.to_dict())
	target.load_dict(receiver.to_dict())
	return ""
