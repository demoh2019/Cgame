extends RefCounted
## Scent camouflage is an inventory-paid, temporary stealth tool.
## It prevents only blood-scent acquisition: infected still see, hear,
## remember, and pursue players using their normal rules.

const ITEM_ID := "herbal_scent_mask"
const DURATION_SECONDS := 120.0


static func can_apply(survival) -> bool:
	if survival == null or not survival.alive:
		return false
	var current: float = survival.scent_mask_seconds
	return is_finite(current) and current == 0.0


## Called only by server after a successful item debit.
static func apply(survival) -> void:
	survival.scent_mask_seconds = DURATION_SECONDS


static func active(survival) -> bool:
	return survival != null and survival.alive and is_finite(survival.scent_mask_seconds) and survival.scent_mask_seconds > 0.0
