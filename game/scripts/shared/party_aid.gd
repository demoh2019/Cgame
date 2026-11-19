extends RefCounted
## Authoritative, equipment-independent field medic support for survivor parties.
## Client requests only recipient and carried item; server owns all other rules.

const Defs = preload("res://scripts/shared/defs.gd")
const RANGE := 3.2
const MAX_HEIGHT_DIFF := 2.5
const COOLDOWN := 5.0


static func can_reach(source: Vector3, target: Vector3) -> bool:
	if not source.is_finite() or not target.is_finite():
		return false
	if absf(source.y - target.y) > MAX_HEIGHT_DIFF:
		return false
	var offset := Vector2(source.x - target.x, source.z - target.z)
	return offset.length_squared() <= RANGE * RANGE


static func has_effect(item_data: Dictionary, health: float, infection: float) -> bool:
	if str(item_data.get("kind", "")) != "medical":
		return false
	if not is_finite(health) or not is_finite(infection):
		return false
	var heal_amount: float = float(item_data.get("heal", 0.0))
	var cure_amount: float = float(item_data.get("cure", 0.0))
	return (heal_amount > 0.0 and health < Defs.MAX_HEALTH) or (
		cure_amount > 0.0 and infection > 0.0)
