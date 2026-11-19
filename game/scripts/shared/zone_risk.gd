extends RefCounted
## Authoritative world risk. Yellow is PvE-only in this MVP.

const Defs = preload("res://scripts/shared/defs.gd")

static func allows_pvp(zone: int) -> bool:
	return zone >= 2 and zone < Defs.ZONE_NAMES.size()

static func can_pvp(attacker_zone: int, victim_zone: int) -> bool:
	return allows_pvp(attacker_zone) and allows_pvp(victim_zone)

static func full_loot(zone: int) -> bool:
	return allows_pvp(zone)

static func description(zone: int) -> String:
	if zone == 0 or zone == 1:
		return "PvE | Equipment retained"
	if allows_pvp(zone):
		return "PvP | Full loot"
	return "Unknown risk"
