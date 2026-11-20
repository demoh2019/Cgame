extends RefCounted
## Item-paid, server-only group triage after battles.
## This helper is pure: clients cannot supply recipients, effects or positions.

const ITEM_ID := "field_triage_pack"
const RANGE := 5.5
const HEIGHT_LIMIT := 2.5
const MAX_RECIPIENTS := 3
const HEAL := 18.0
const BLEEDING_TREATMENT := 24.0
const COOLDOWN := 18.0


static func can_reach(source: Vector3, target: Vector3) -> bool:
	if not source.is_finite() or not target.is_finite():
		return false
	if absf(source.y - target.y) > HEIGHT_LIMIT:
		return false
	var offset := Vector2(source.x - target.x, source.z - target.z)
	return offset.length_squared() <= RANGE * RANGE


## Greater score receives care first. Never treat healthy or invalid targets.
static func urgency(health: float, max_health: float, bleeding: float) -> float:
	if not is_finite(health) or not is_finite(max_health) or not is_finite(bleeding):
		return 0.0
	if max_health <= 0.0 or health <= 0.0 or health > max_health:
		return 0.0
	if bleeding < 0.0 or bleeding > 100.0:
		return 0.0
	return minf(HEAL, maxf(0.0, max_health - health)) + \
		minf(BLEEDING_TREATMENT, bleeding) * 0.6
