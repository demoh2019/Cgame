extends RefCounted
## A physical T2 pack distributes finite on-foot carry load. It never grants
## inventory slots, removes mass, prevents PvP drops or stacks with panniers.
const ITEM_ID := "trail_backpack_2"
const SUPPORTED_KG := 14.0


static func installed(inventory) -> bool:
	return inventory != null and inventory.count(ITEM_ID) > 0


static func support_kg(inventory, mounted: bool = false) -> float:
	return SUPPORTED_KG if not mounted and installed(inventory) else 0.0


static func effective_weight(inventory) -> float:
	if inventory == null:
		return 0.0
	return maxf(0.0, inventory.total_weight() - support_kg(inventory))
