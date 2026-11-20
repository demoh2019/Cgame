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


## Only plain provisions can be handed over. Special meals and potions retain
## their separate gameplay rules; clients cannot submit an arbitrary item ID.
static func supported_item(item_id: String, item_data: Dictionary) -> bool:
	match item_id:
		"berries", "canned_food":
			return str(item_data.get("kind", "")) == "food" and float(item_data.get("food", 0.0)) > 0.0
		"water_bottle":
			return str(item_data.get("kind", "")) == "drink" and float(item_data.get("drink", 0.0)) > 0.0
		_:
			return str(item_data.get("kind", "")) == "medical"


static func has_effect(item_data: Dictionary, health: float, infection: float,
		bleeding: float = 0.0, fracture: float = 0.0,
		hunger: float = 100.0, thirst: float = 100.0) -> bool:
	if not is_finite(health) or not is_finite(infection) or not is_finite(bleeding) or \
			not is_finite(fracture) or not is_finite(hunger) or not is_finite(thirst):
		return false
	match str(item_data.get("kind", "")):
		"food":
			return float(item_data.get("food", 0.0)) > 0.0 and hunger < 100.0
		"drink":
			return float(item_data.get("drink", 0.0)) > 0.0 and thirst < 100.0
		"medical":
			var heal_amount: float = float(item_data.get("heal", 0.0))
			var cure_amount: float = float(item_data.get("cure", 0.0))
			return (heal_amount > 0.0 and health < Defs.MAX_HEALTH) or (
				cure_amount > 0.0 and infection > 0.0) or (
				bool(item_data.get("stop_bleeding", false)) and bleeding > 0.0) or (
				float(item_data.get("fracture_treatment", 0.0)) > 0.0 and fracture > 0.0)
	return false
