extends RefCounted
## Deterministic elite encounters in dangerous ruins. Server owns eligibility,
## combat statistics and loot; none of these are sent as client commands.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const MIN_ZONE := 2
const RARITY := 7
const HEALTH_MULTIPLIER := 2.5
const DAMAGE_MULTIPLIER := 1.4
const MASTERY_XP_MULTIPLIER := 3


static func is_elite_spawn(spawn_id: int, zone: int, in_ruins: bool, seed: int) -> bool:
	if spawn_id <= 0 or zone < MIN_ZONE or zone > 3 or not in_ruins:
		return false
	return WorldGen.mix(spawn_id, zone, seed, 87) % RARITY == 0


## Important: duplicate the nested dictionary from Defs.ZOMBIES. Changing
## class-wide zombie data would promote every infected in the simulation.
static func empowered_stats(base: Dictionary) -> Dictionary:
	var stats: Dictionary = base.duplicate(true)
	stats["health"] = float(base["health"]) * HEALTH_MULTIPLIER
	stats["damage"] = float(base["damage"]) * DAMAGE_MULTIPLIER
	stats["xp"] = int(base["xp"]) * MASTERY_XP_MULTIPLIER
	return stats


## All loot is placed in the ordinary world loot bag (no instant transfer).
## Loot from an ordinary infected is not mutated by this helper.
static func enhanced_loot(normal_loot: Dictionary, zone: int) -> Dictionary:
	var result: Dictionary = normal_loot.duplicate(true)
	if zone < MIN_ZONE or zone > 3:
		return result
	result["infected_core"] = int(result.get("infected_core", 0)) + 1
	result["silver"] = int(result.get("silver", 0)) + 8 * (zone + 1)
	result["scrap"] = int(result.get("scrap", 0)) + 2 * (zone + 1)
	return result
