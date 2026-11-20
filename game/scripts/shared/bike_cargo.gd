extends RefCounted
## Crafted saddlebags shift part of carried weight onto an owned bicycle.
## They do NOT create inventory slots, reduce loot/drop weight or improve on-foot speed.

const Defs = preload("res://scripts/shared/defs.gd")

const ITEM_ID := "bike_panniers"
const BIKE_ID := "salvage_bike"
const SUPPORTED_KG := 28.0


static func installed(inventory) -> bool:
	return inventory.count(BIKE_ID) > 0 and inventory.count(ITEM_ID) > 0


static func effective_weight(inventory, riding: bool) -> float:
	var weight: float = inventory.total_weight()
	if riding and installed(inventory):
		return maxf(0.0, weight - SUPPORTED_KG)
	return weight


static func movement_factor(inventory, skill_bonus: float, riding: bool) -> float:
	# Inventory.weight is the only source of truth; this is never supplied by a client RPC.
	var capacity := 1.0 + maxf(skill_bonus, 0.0)
	return Defs.carry_speed_factor(effective_weight(inventory, riding) / capacity)
