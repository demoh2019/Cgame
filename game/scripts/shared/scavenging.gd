extends RefCounted
## Server-only scavenging risk/reward rules for real, one-use ruin crates.
## No client-controlled loot, XP, bonus count or zone values.

const Defs = preload("res://scripts/shared/defs.gd")
const XP_BY_ZONE := [15, 20, 30, 45]
const XP_PER_LEVEL := 75
const MAX_LEVEL := 5


static func xp_for_zone(zone: int) -> int:
	if zone < 0 or zone >= XP_BY_ZONE.size():
		return 0
	return int(XP_BY_ZONE[zone])


static func level_for_xp(xp: int) -> int:
	return mini(MAX_LEVEL, 1 + maxi(0, xp) / XP_PER_LEVEL)


## Extra mundane salvage; valuable weapons/medicine remain ordinary RNG loot.
## Only red/black crates at level >= 2 get an additional, bounded scrap yield.
static func enriched_loot(zone: int, level: int, base: Dictionary) -> Dictionary:
	var loot: Dictionary = base.duplicate(true)
	if zone < 2 or zone >= XP_BY_ZONE.size() or level < 2:
		return loot
	var bonus: int = mini(MAX_LEVEL - 1, level - 1)
	loot["scrap"] = int(loot.get("scrap", 0)) + bonus
	return loot
