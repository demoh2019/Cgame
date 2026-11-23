extends RefCounted
## Authoritative, equipment-independent field medic support for survivor parties.
## Client requests only recipient and carried item; server owns all other rules.

const Defs = preload("res://scripts/shared/defs.gd")
const WoundSealant = preload("res://scripts/shared/wound_sealant.gd")
const RANGE := 3.2
const MAX_HEIGHT_DIFF := 2.5
const COOLDOWN := 5.0


static func can_reach(source: Vector3, target: Vector3) -> bool:
	if not source.is_finite() or not target.is_finite():
		return false
	if absf(source.y - target.y) > MAX_HEIGHT_DIFF:
		return false
	var offset := Vector2(source.x - target.x, source.z - target.z)
	var distance_squared: float = offset.length_squared()
	return is_finite(distance_squared) and distance_squared <= RANGE * RANGE


## Only plain provisions can be handed over. Special meals and potions retain
## their separate gameplay rules; clients cannot submit an arbitrary item ID.
static func supported_item(item_id: String, item_data: Dictionary) -> bool:
	match item_id:
		"berries", "canned_food":
			return str(item_data.get("kind", "")) == "food" and \
				_positive_stat(item_data, "food")
		"water_bottle":
			return str(item_data.get("kind", "")) == "drink" and \
				_positive_stat(item_data, "drink")
		_:
			if item_id == WoundSealant.ITEM_ID:
				return str(item_data.get("kind", "")) == "wound_seal"
			return str(item_data.get("kind", "")) == "medical"


static func _positive_stat(data: Dictionary, key: String) -> bool:
	var raw: Variant = data.get(key, 0.0)
	if not (raw is int or raw is float):
		return false
	var value: float = float(raw)
	return is_finite(value) and value > 0.0


static func has_effect(item_data: Dictionary, health: float, infection: float,
		bleeding: float = 0.0, fracture: float = 0.0,
		hunger: float = 100.0, thirst: float = 100.0,
		max_health: float = Defs.MAX_HEALTH, food_poisoning: float = 0.0) -> bool:
	if not is_finite(health) or not is_finite(infection) or not is_finite(bleeding) or \
			not is_finite(fracture) or not is_finite(hunger) or not is_finite(thirst) or \
			not is_finite(max_health) or max_health <= 0.0 or \
			not is_finite(food_poisoning) or food_poisoning < 0.0:
		return false
	match str(item_data.get("kind", "")):
		"food":
			return _positive_stat(item_data, "food") and hunger < 100.0
		"drink":
			return _positive_stat(item_data, "drink") and thirst < 100.0
		"medical":
			return (_positive_stat(item_data, "heal") and health < max_health) or (
				_positive_stat(item_data, "cure") and infection > 0.0) or (
				bool(item_data.get("stop_bleeding", false)) and bleeding > 0.0) or (
				_positive_stat(item_data, "fracture_treatment") and fracture > 0.0) or (
				_positive_stat(item_data, "food_poison_treatment") and food_poisoning > 0.0)
	return false


## One catalog for the UI and server, so newly crafted medical items work in
## cooperative play without maintaining a second, incomplete whitelist.
static func medical_items() -> Array[String]:
	var result: Array[String] = []
	for raw_id in Defs.items():
		var item_id: String = str(raw_id)
		var kind: String = str(Defs.item(item_id).get("kind", ""))
		if kind == "medical" or (item_id == WoundSealant.ITEM_ID and kind == "wound_seal"):
			result.append(item_id)
	result.sort()
	return result


## Automatic field aid is a convenience request, never a client-selected target
## condition. Use the cheapest carried remedy for the most urgent treatable
## condition: bleeding, fracture, infection, then missing health.
## Manual item selection stays available for deliberate expensive treatments.
static func best_item(inventory, health: float, infection: float,
		bleeding: float, fracture: float, max_health: float = Defs.MAX_HEALTH,
		food_poisoning: float = 0.0) -> String:
	if inventory == null or not is_finite(health) or not is_finite(infection) or \
			not is_finite(bleeding) or not is_finite(fracture) or not is_finite(max_health) or \
			not is_finite(food_poisoning):
		return ""
	if health < 0.0 or max_health <= 0.0 or health > max_health or \
			infection < 0.0 or infection > Defs.INFECTION_MAX or \
			bleeding < 0.0 or bleeding > Defs.BLEEDING_MAX or \
			fracture < 0.0 or fracture > Defs.FRACTURE_MAX or \
			food_poisoning < 0.0 or food_poisoning > 100.0:
		return ""
	var selected := ""
	var selected_priority := 99
	var selected_value := 2_147_483_647
	for item_id in medical_items():
		if inventory.count(item_id) < 1:
			continue
		var data: Dictionary = Defs.item(item_id)
		if not has_effect(data, health, infection, bleeding, fracture, 100.0, 100.0,
			max_health, food_poisoning):
			continue
		var priority := 4
		if bleeding > 0.0 and bool(data.get("stop_bleeding", false)):
			priority = 0
		elif fracture > 0.0 and float(data.get("fracture_treatment", 0.0)) > 0.0:
			priority = 1
		elif infection > 0.0 and float(data.get("cure", 0.0)) > 0.0:
			priority = 2
		elif food_poisoning > 0.0 and float(data.get("food_poison_treatment", 0.0)) > 0.0:
			priority = 3
		var value: int = maxi(0, int(data.get("value", 0)))
		var better: bool = priority < selected_priority
		if priority == selected_priority:
			better = value < selected_value or (value == selected_value and item_id < selected)
		if better:
			selected = item_id
			selected_priority = priority
			selected_value = value
	return selected
