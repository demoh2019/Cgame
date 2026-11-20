extends RefCounted
## Authoritative medicine mastery for parties. No client-provided bonus or XP.
## PvP-safe group treatment uses a smaller cap than self-healing perks.

const MAX_PARTY_HEAL_BONUS := 0.35
const MAX_TRAINING_XP := 5.0
const MIN_TRAINING_EFFORT := 1.0


## Returns the amount to hand to Survival.heal, not the actual credited heal.
## The server measures real HP restored after the recipient's max-HP clamp.
static func heal_amount(base_amount: float, medic_bonus: float) -> float:
	if not is_finite(base_amount) or base_amount <= 0.0 or \
			not is_finite(medic_bonus) or medic_bonus < 0.0:
		return 0.0
	return base_amount * (1.0 + minf(medic_bonus, MAX_PARTY_HEAL_BONUS))


## Real inventory-paid medical effects train the Medic skill, never supplies,
## idle casts or failed RPCs. Do not award points for tiny/no-op health changes.
## Each action has a hard XP cap, including three-target group triage.
static func training_xp(healed: float, bleeding_stopped: float,
		infection_cured: float, fracture_treated: float, poisoning_treated: float) -> float:
	for value in [healed, bleeding_stopped, infection_cured,
			fracture_treated, poisoning_treated]:
		if not is_finite(value) or value < 0.0:
			return 0.0
	var effort: float = healed / 12.0 + bleeding_stopped / 24.0 + \
		infection_cured / 25.0 + fracture_treated / 30.0 + poisoning_treated / 25.0
	if effort < MIN_TRAINING_EFFORT:
		return 0.0
	return minf(MAX_TRAINING_XP, effort)
