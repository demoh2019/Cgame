extends RefCounted
## Paid hub and field recovery grants a bounded extra-XP reserve.
## Only GameServer._award converts this reserve into character experience.

const MAX_CREDIT := 240
const HUB_GRANT := 60
const FIELD_GRANT := 30
const BONUS_RATE := 0.50
const DEVELOPING_RATE := 0.60
const NOVICE_RATE := 0.75
const NOVICE_UNTIL := 10
const DEVELOPING_UNTIL := 25


static func valid_credit(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= float(MAX_CREDIT) and \
		number == floor(number)


static func refill(current: int, field: bool) -> int:
	if current < 0 or current > MAX_CREDIT:
		return 0
	return mini(MAX_CREDIT, current + (FIELD_GRANT if field else HUB_GRANT))


## A higher learning rate helps a survivor catch up in weaker skill lines.
## At levels 1-9: 75%; 10-24: 60%; 25+: 50%. All rates spend the
## same bounded extra-XP credit, never grant XP without a real skill action.
static func rate_for_level(skill_level: int) -> float:
	if skill_level <= 0:
		return 0.0
	if skill_level < NOVICE_UNTIL:
		return NOVICE_RATE
	if skill_level < DEVELOPING_UNTIL:
		return DEVELOPING_RATE
	return BONUS_RATE


## Credit is measured in *additional*, not base, skill XP. Invalid input,
## fractional spam and exhausted reserves cannot mint a bonus.
static func bonus_for(amount: float, credit: int, skill_level: int = DEVELOPING_UNTIL) -> int:
	if not is_finite(amount) or amount <= 0.0 or credit <= 0 or credit > MAX_CREDIT or skill_level <= 0:
		return 0
	return mini(credit, maxi(0, roundi(minf(amount, 100000.0) * rate_for_level(skill_level))))
