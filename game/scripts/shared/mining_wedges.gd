extends RefCounted
## High-tier mining preparation trades extra yield for louder infected hearing.
## A single paid kit grants three server-verified, capacity-aware harvests.

const ITEM_ID := "mining_wedges"
const CHARGES := 3
const EXTRA_YIELD := 2
const MIN_TIER := 2
const NOISE_RADIUS := 42.0


## Saved integer charges are a bounded legacy-compatible account field.
static func valid_state(value: Variant) -> bool:
	return value is int and value >= 0 and value <= CHARGES


static func use_reason(inventory, charges: int) -> String:
	if not valid_state(charges):
		return "invalid_state"
	if charges > 0:
		return "already_prepared"
	if inventory.best_tool("pickaxe") == "":
		return "need_pickaxe"
	return ""


## Only real T2+ rock/ore gathers can spend a charge. The entire ordinary
## harvest plus bonus must fit, otherwise keep the charge and ordinary yield.
## No PvP, wood, berry, quest or fishing reward can trigger this bonus.
static func bonus(kind: String, tier: int, charges: int,
		free_space: int, ordinary_amount: int, authenticated: bool) -> int:
	if not authenticated or not valid_state(charges) or charges <= 0:
		return 0
	if kind not in ["ore", "rock"] or tier < MIN_TIER or tier > 4:
		return 0
	if ordinary_amount <= 0 or free_space < ordinary_amount + EXTRA_YIELD:
		return 0
	return EXTRA_YIELD


static func harvest_noise(base: float, bonus_added: int) -> float:
	if not is_finite(base):
		return 0.0
	return maxf(base, NOISE_RADIUS) if bonus_added == EXTRA_YIELD else maxf(0.0, base)
