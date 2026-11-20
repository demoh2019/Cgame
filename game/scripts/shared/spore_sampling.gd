extends RefCounted
## Risky world-bound gathering. Failed inventory transfers cannot consume a kit,
## and only the server can decide the actual swamp, source and exposure.

const Inventory = preload("res://scripts/shared/inventory.gd")
const KIT_ID := "spore_sampler"
const CULTURE_ID := "spore_culture"
const CULTURES_PER_KIT := 2
const COOLDOWN_SECONDS := 150.0
const BASE_INFECTION := 5.0


static func site_reason(world, position: Vector3) -> String:
	if not position.is_finite():
		return "invalid_position"
	if world.is_safe(position.x, position.z):
		return "safe_zone"
	if world.is_water(position.x, position.z):
		return "in_water"
	if world.zone_at(position.x, position.z) < 1:
		return "safe_zone"
	if world.biome_at(position.x, position.z) != "swamp":
		return "no_spores"
	return ""


static func infection_cost(protection: float) -> float:
	if not is_finite(protection):
		return BASE_INFECTION
	return BASE_INFECTION * (1.0 - clampf(protection, 0.0, 0.95))


static func transact(inventory: Inventory) -> Dictionary:
	if inventory.count(KIT_ID) < 1:
		return {"ok": false, "reason": "no_sample_kit"}
	var trial := Inventory.new(inventory.slots.size())
	trial.load_dict(inventory.to_dict())
	if not trial.remove(KIT_ID, 1):
		return {"ok": false, "reason": "no_sample_kit"}
	if trial.add(CULTURE_ID, CULTURES_PER_KIT) != 0:
		return {"ok": false, "reason": "no_space"}
	inventory.load_dict(trial.to_dict())
	return {"ok": true, "count": CULTURES_PER_KIT}
