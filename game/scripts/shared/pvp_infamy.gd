extends RefCounted
## Server-owned PvP reputation, only changed by confirmed lethal player hits.

const MAX_INFAMY := 100.0
const INFAMY_PER_KILL := 25.0
const OUTLAW_THRESHOLD := 50.0
const SECONDS_PER_POINT := 180.0


static func valid(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var score: float = float(value)
	return is_finite(score) and score >= 0.0 and score <= MAX_INFAMY


static func is_outlaw(score: float) -> bool:
	return valid(score) and score >= OUTLAW_THRESHOLD


static func gain_for_kill(score: float) -> float:
	if not valid(score):
		return 0.0
	return minf(MAX_INFAMY, score + INFAMY_PER_KILL)


static func decay(score: float, seconds: float) -> float:
	if not valid(score):
		return 0.0
	if not is_finite(seconds) or seconds <= 0.0:
		return score
	return maxf(0.0, score - seconds / SECONDS_PER_POINT)


## Price for one item, independent of batch size (no split-order exploit).
## Infamy raises buy prices at most 50% and lowers sell prices at most 25%.
static func vendor_unit_price(base_price: int, score: float, buy: bool) -> int:
	if base_price < 1 or not valid(score):
		return 0
	if buy:
		return ceili(float(base_price) * (1.0 + 0.5 * score / MAX_INFAMY))
	return maxi(1, roundi(float(base_price) * (1.0 - 0.25 * score / MAX_INFAMY)))
