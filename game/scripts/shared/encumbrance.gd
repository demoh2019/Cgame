extends RefCounted
## Shared, deterministic, integer-gram carrying rules for the authoritative
## game in game/. Uses existing item kinds and tiers; never trusts a client's
## reported weight. A tool or equipped weapon is already in the inventory and
## is therefore counted once, not twice.

const Defs = preload("res://scripts/shared/defs.gd")

const FREE_KG := 12.0
const NO_SPRINT_KG := 18.0
const FULL_PENALTY_KG := 38.0
const MIN_SPEED_FACTOR := 0.45


static func item_grams(id: String) -> int:
	var data: Dictionary = Defs.item(id)
	if data.is_empty():
		return 0
	var tier := maxi(int(data.get("tier", 1)), 1)
	match str(data.get("kind", "")):
		"resource":
			if id.begins_with("fiber_"):
				return 350 * tier
			if id.begins_with("wood_"):
				return 1700 * tier
			if id.begins_with("stone_") or id.begins_with("ore_"):
				return 2400 * tier
			return 1300 * tier # Scrap and other salvage
		"material":
			if id.begins_with("cloth_"):
				return 250 * tier
			if id.begins_with("plank_"):
				return 900 * tier
			return 1700 * tier
		"tool":
			return 2000 * tier
		"weapon":
			return 2600 * tier
		"armor":
			return 3200 * tier
		"food":
			return 500
		"drink":
			return 1000
		"medical":
			return 200
		"ammo":
			return 30
		"currency":
			return 0
	return 1000


static func sprint_allowed(grams: int) -> bool:
	return grams < int(NO_SPRINT_KG * 1000.0)


static func speed_factor(grams: int) -> float:
	var kg := float(maxi(grams, 0)) / 1000.0
	if kg <= FREE_KG:
		return 1.0
	return lerpf(1.0, MIN_SPEED_FACTOR,
		clampf((kg - FREE_KG) / (FULL_PENALTY_KG - FREE_KG), 0.0, 1.0))
