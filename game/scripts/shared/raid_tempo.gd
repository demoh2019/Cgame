extends RefCounted
## Optional raid tempo chest bonus: only the authoritative encounter clock
## decides the tier; normal zombies and ordinary boss treasure are unchanged.
const GOLD_LIMIT := 90.0
const SILVER_LIMIT := 150.0

static func rank(elapsed: float) -> String:
	if not is_finite(elapsed) or elapsed < 0.0:
		return ""
	if elapsed <= GOLD_LIMIT:
		return "gold"
	if elapsed <= SILVER_LIMIT:
		return "silver"
	return ""

static func bonus(zone: int, elapsed: float) -> Dictionary:
	if zone < 2 or zone > 3:
		return {}
	var grade: String = rank(elapsed)
	var tier: int = zone + 1
	if grade == "gold":
		return {"silver": 25 * tier, "infected_core": 2}
	if grade == "silver":
		return {"silver": 12 * tier, "infected_core": 1}
	return {}
