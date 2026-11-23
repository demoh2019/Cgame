extends RefCounted
## Server-side requirements for temporary group food and water alerts.
## Never trust a client-reported survival stat, timestamp or position.

const NEED_THRESHOLD := 60.0
const COOLDOWN := 30.0
const ALERT_SECONDS := 45.0 # Temporary aid location; no persistent tracking.


static func valid_need(need: String) -> bool:
	return need == "food" or need == "water"


static func level(need: String, hunger: float, thirst: float) -> float:
	if not is_finite(hunger) or not is_finite(thirst):
		return -1.0
	match need:
		"food":
			return hunger
		"water":
			return thirst
	return -1.0


static func eligible(need: String, hunger: float, thirst: float) -> bool:
	var value: float = level(need, hunger, thirst)
	return valid_need(need) and value >= 0.0 and value <= NEED_THRESHOLD


static func can_send(now: float, last_at: float) -> bool:
	if not is_finite(now) or now < 0.0:
		return false
	if last_at == -INF: # First request in this server session.
		return true
	# Reject a future or corrupt last-send timestamp. Subtracting two
	# valid nonnegative server times avoids overflowing the deadline sum.
	return is_finite(last_at) and last_at >= 0.0 and now >= last_at and \
		is_finite(now - last_at) and now - last_at >= COOLDOWN
