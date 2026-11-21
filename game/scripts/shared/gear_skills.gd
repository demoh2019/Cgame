extends RefCounted
## Albion Online-style gear-defined ability bar. Your build IS your class:
##   Q  - the weapon's skill (Combat.active_skill, existing G key)
##   E  - the weapon's ultimate: a charged version of Q, long cooldown
##   R  - chest armor: Iron Skin (damage reduction for a few seconds)
##   D  - helmet: Second Wind (heal over time)
##   F  - boots: Sprint (movement speed burst)
## Strength scales with item power (tier + enchant). Cooldowns are per slot and
## everything is validated on the server; the client only sends the slot.

const Defs = preload("res://scripts/shared/defs.gd")

const SLOTS := ["armor", "head", "feet"]
const ULTIMATE_DAMAGE := 2.2
const ULTIMATE_COOLDOWN := 3.0
const ULTIMATE_ENERGY := 1.6
const MAX_GUARD := 0.5
const MAX_SPEED := 0.4


## Item-power scale: 1.0 at T1 flat (400 IP), +12.5% per 100 IP.
static func power_scale(item_id: String) -> float:
	return 1.0 + maxf(0.0, float(Defs.item_power(item_id) - 400)) / 800.0


## The armor-slot skill granted by an equipped item, or {} when the slot is empty/unknown.
static func skill_for(slot: String, item_id: String) -> Dictionary:
	if item_id == "" or Defs.item(item_id).is_empty():
		return {}
	var s: float = power_scale(item_id)
	match slot:
		"armor":
			return {"id": "iron_skin", "slot": "armor", "cooldown": 25.0, "seconds": 4.0,
				"guard": minf(MAX_GUARD, 0.25 * s)}
		"head":
			return {"id": "second_wind", "slot": "head", "cooldown": 30.0, "seconds": 6.0,
				"heal_total": 14.0 * s}
		"feet":
			return {"id": "sprint", "slot": "feet", "cooldown": 18.0, "seconds": 4.0,
				"speed": minf(MAX_SPEED, 0.25 * s)}
	return {}


## The weapon's ultimate (E): Q's skill charged up.
static func ultimate(skill: Dictionary) -> Dictionary:
	if skill.is_empty():
		return {}
	var charged: Dictionary = skill.duplicate(true)
	charged["id"] = str(skill.get("id", "skill")) + "_ultimate"
	charged["damage"] = float(skill.get("damage", 0.0)) * ULTIMATE_DAMAGE
	charged["cooldown"] = float(skill.get("cooldown", 5.0)) * ULTIMATE_COOLDOWN
	charged["energy_cost"] = float(skill.get("energy_cost", 20.0)) * ULTIMATE_ENERGY
	if charged.has("party_heal"):
		charged["party_heal"] = float(charged["party_heal"]) * ULTIMATE_DAMAGE
	return charged


## Item equipped in an armor-type slot of an inventory.
static func equipped_in(inventory, slot: String) -> String:
	var id: String = inventory.armor if slot == "armor" else str(inventory.gear.get(slot, ""))
	return id if id != "" and inventory.count(id) > 0 else ""
