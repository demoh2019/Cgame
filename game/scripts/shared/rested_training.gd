extends RefCounted
## Paid hub and field recovery grants a bounded extra-XP reserve.
## Only GameServer._award converts this reserve into character experience.

const MAX_CREDIT := 120
const HUB_GRANT := 30
const FIELD_GRANT := 15
const BONUS_RATE := 0.25


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


## Credit is measured in *additional*, not base, skill XP. Partial XP,
## malformed amounts and already exhausted reserves never create a bonus.
static func bonus_for(amount: float, credit: int) -> int:
	if not is_finite(amount) or amount <= 0.0 or credit <= 0 or credit > MAX_CREDIT:
		return 0
	return mini(credit, maxi(0, roundi(minf(amount, 100000.0) * BONUS_RATE)))
