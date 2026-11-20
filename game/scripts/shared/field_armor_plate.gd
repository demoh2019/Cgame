extends RefCounted
## Limited, paid armor preparation against ordinary infected claws.
const Defs = preload("res://scripts/shared/defs.gd")

const ITEM_ID := "field_armor_plate"
const HITS := 3
const DAMAGE_FACTOR := 0.80


static func armor_equipped(inventory) -> String:
	var armor: String = inventory.armor
	if armor.is_empty() or inventory.count(armor) < 1:
		return ""
	if str(Defs.item(armor).get("kind", "")) != "armor":
		return ""
	return armor


static func valid_state(armor: Variant, hits: Variant, inventory) -> bool:
	if not (armor is String) or not (hits is int):
		return false
	if hits < 0 or hits > HITS:
		return false
	if hits == 0:
		return armor == ""
	return armor != "" and armor == armor_equipped(inventory)


static func active(armor: String, hits: int, inventory) -> bool:
	return hits > 0 and valid_state(armor, hits, inventory)
