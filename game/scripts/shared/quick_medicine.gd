extends RefCounted
## Server-owned medicine selection; all effects and item costs use cmd_use.
const MIN_HEAL_DEFICIT := 10.0


static func _first_carried(inventory, choices: Array) -> String:
	for id in choices:
		if inventory.count(str(id)) > 0:
			return str(id)
	return ""


static func pick(inventory, survivor) -> String:
	if inventory == null or survivor == null or not survivor.alive:
		return ""
	if not is_finite(survivor.health) or not is_finite(survivor.max_health) or \
			not is_finite(survivor.infection) or not is_finite(survivor.bleeding) or \
			not is_finite(survivor.fracture):
		return ""
	var missing: float = maxf(0.0, survivor.max_health - survivor.health)
	var picked := ""
	if survivor.fracture > 0.0:
		picked = _first_carried(inventory, ["field_splint"])
		if not picked.is_empty():
			return picked
	if survivor.bleeding > 0.0:
		picked = _first_carried(inventory,
			["bandage", "herbal_poultice", "field_antiseptic"])
		if not picked.is_empty():
			return picked
	if survivor.infection >= 75.0:
		picked = _first_carried(inventory,
			["antibiotics", "spore_antidote", "purified_serum",
			"field_antiseptic", "herbal_poultice"])
	elif survivor.infection >= 40.0:
		picked = _first_carried(inventory,
			["spore_antidote", "field_antiseptic", "purified_serum",
			"antibiotics", "herbal_poultice"])
	elif survivor.infection >= 18.0:
		picked = _first_carried(inventory,
			["field_antiseptic", "herbal_poultice", "purified_serum",
			"spore_antidote", "antibiotics"])
	if not picked.is_empty():
		return picked
	if missing >= 18.0:
		picked = _first_carried(inventory,
			["bandage", "herbal_poultice", "purified_serum", "field_antiseptic"])
		if not picked.is_empty():
			return picked
	if survivor.infection > 0.0:
		picked = _first_carried(inventory,
			["herbal_poultice", "field_antiseptic", "purified_serum",
			"spore_antidote", "antibiotics"])
		if not picked.is_empty():
			return picked
	if missing >= MIN_HEAL_DEFICIT:
		return _first_carried(inventory,
			["herbal_poultice", "bandage", "purified_serum", "field_antiseptic"])
	return ""
