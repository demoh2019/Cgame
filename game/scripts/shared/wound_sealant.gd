extends RefCounted
## Paid, nonstacking field dressing against physical zombie melee infection.
## Acid, ambient spores, injury damage, bleeding and PvP remain unchanged.

const ITEM_ID := "wound_sealant"
const DURATION_SECONDS := 90.0
const INFECTION_FACTOR := 0.55


static func mitigate(infection: float, remaining: float) -> float:
	if not is_finite(infection) or infection <= 0.0:
		return 0.0
	if not is_finite(remaining) or remaining <= 0.0:
		return infection
	return infection * INFECTION_FACTOR
