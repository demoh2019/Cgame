extends RefCounted
## Deterministic airborne infection in dangerous swamps.
## The server supplies world position, time and physically equipped armor.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")

const DAY_INFECTION_PER_SECOND := 0.14
const NIGHT_INFECTION_PER_SECOND := 0.28

# Disposable field respirator: protects only against ambient swamp spores.
# Combining it with sealed armor has diminishing returns; at least 5% gets through.
const FILTER_ITEM_ID := "spore_filter"
const FILTER_DURATION_SECONDS := 120.0
const FILTER_REDUCTION := 0.75
const MAX_PROTECTION := 0.95


static func protection(armor_id: String) -> float:
	var data: Dictionary = Defs.item(armor_id)
	if str(data.get("kind", "")) != "armor":
		return 0.0
	return clampf(float(data.get("spore_resistance", 0.0)), 0.0, 0.95)


## A pure, snapshot-safe hazard state (no client input or writable state).
static func status(world, position: Vector3, world_seconds: float,
		equipped_armor: String = "", filter_seconds: float = 0.0) -> Dictionary:
	var clean := {"active": false, "rate": 0.0, "protection": 0.0}
	if not position.is_finite() or not is_finite(world_seconds) or world_seconds < 0.0:
		return clean
	if world.is_safe(position.x, position.z):
		return clean
	if world.zone_at(position.x, position.z) < 1 or world.biome_at(position.x, position.z) != "swamp":
		return clean
	var resistance: float = protection(equipped_armor)
	if is_finite(filter_seconds) and filter_seconds > 0.0 and filter_seconds <= FILTER_DURATION_SECONDS:
		resistance = minf(MAX_PROTECTION,
			1.0 - (1.0 - resistance) * (1.0 - FILTER_REDUCTION))
	var base: float = NIGHT_INFECTION_PER_SECOND if WorldCycle.is_night(world_seconds) else DAY_INFECTION_PER_SECOND
	return {"active": true, "rate": base * (1.0 - resistance), "protection": resistance}
