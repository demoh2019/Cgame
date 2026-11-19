extends RefCounted
## Rare, crafted combat stimulant: immediate recovery paid for with thirst.
## Activation and cooldown are server owned; relog or death never resets it.

const Defs = preload("res://scripts/shared/defs.gd")

const ITEM_ID := "frontier_stim"
const COOLDOWN := 90.0
const STAMINA_RESTORE := 50.0
const ENERGY_RESTORE := 35.0
const THIRST_COST := 12.0
const MIN_TOTAL_DEFICIT := 20.0


static func ready(survival, energy: float, cooldown: float) -> String:
	if survival == null or not survival.alive:
		return "dead"
	if not (is_finite(energy) and is_finite(cooldown) and
			is_finite(survival.stamina) and is_finite(survival.thirst)):
		return "invalid_state"
	if (energy < 0.0 or energy > Defs.COMBAT_ENERGY_MAX or
			survival.stamina < 0.0 or survival.stamina > Defs.MAX_STAMINA or
			survival.thirst < 0.0 or survival.thirst > 100.0 or
			cooldown < 0.0 or cooldown > COOLDOWN):
		return "invalid_state"
	if cooldown > 0.0:
		return "cooldown"
	if survival.thirst < THIRST_COST:
		return "too_thirsty"
	var missing_stamina: float = maxf(0.0, Defs.MAX_STAMINA - survival.stamina)
	var missing_energy: float = maxf(0.0, Defs.COMBAT_ENERGY_MAX - energy)
	if missing_stamina + missing_energy < MIN_TOTAL_DEFICIT:
		return "no_effect"
	return ""


## Call only after a server inventory debit succeeds and ready() returned "".
## No health, damage, infection, or armor bonuses: existing PvP stays fair.
static func apply(survival, energy: float) -> float:
	survival.stamina = minf(Defs.MAX_STAMINA, survival.stamina + STAMINA_RESTORE)
	survival.thirst = maxf(0.0, survival.thirst - THIRST_COST)
	return minf(Defs.COMBAT_ENERGY_MAX, energy + ENERGY_RESTORE)
