extends RefCounted
## Settlement recovery: repair the survivor, not a field teleport heal.
## Existing inventory and survival APIs provide atomic ingredient use.

const Defs = preload("res://scripts/shared/defs.gd")

const COOLDOWN := 90.0
const COST := {"wood_1": 2, "canned_food": 1, "water_bottle": 1}
const HEALTH_RECOVERY := 25.0
const STAMINA_RECOVERY := 55.0
const HUNGER_RECOVERY := 15.0
const THIRST_RECOVERY := 15.0


static func needs_recovery(vitals) -> bool:
	return vitals.alive and (
		vitals.health < Defs.MAX_HEALTH - 0.01
		or vitals.stamina < Defs.MAX_STAMINA - 0.01
		or vitals.hunger < 70.0 or vitals.thirst < 70.0)


static func has_supplies(inventory) -> bool:
	for item_id in COST:
		if inventory.count(String(item_id)) < int(COST[item_id]):
			return false
	return true


## Called only after the server has checked hub position, action state,
## life, cooldown and meaningful missing vitals. No partial ingredient debit.
static func recover(inventory, vitals) -> bool:
	if not needs_recovery(vitals) or not has_supplies(inventory):
		return false
	var original: Dictionary = inventory.to_dict()
	for item_id in COST:
		if not inventory.remove(String(item_id), int(COST[item_id])):
			inventory.load_dict(original)
			return false
	vitals.heal(HEALTH_RECOVERY)
	vitals.stamina = minf(Defs.MAX_STAMINA, vitals.stamina + STAMINA_RECOVERY)
	vitals.stamina_recovery_delay = 0.0
	vitals.eat(HUNGER_RECOVERY)
	vitals.drink(THIRST_RECOVERY)
	return true
