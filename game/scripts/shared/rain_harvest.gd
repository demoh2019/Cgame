extends RefCounted
## Weather-driven survival resource loop. All checks are deterministic and
## server-authoritative. Water is paid for with a crafted tarp and, in swamps,
## an actual charcoal filter; no client may claim the rain or choose yields.

const Weather = preload("res://scripts/shared/weather.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")

const TARP_ITEM := "rain_tarp"
const FILTER_ITEM := "charcoal_filter"
const WATER_ITEM := "water_bottle"
const WATER_COUNT := 2
const COOLDOWN_SECONDS := 90.0
const MIN_SLOPE_NORMAL_Y := 0.72


static func site_reason(world, position: Vector3, world_seconds: float) -> String:
	if not position.is_finite() or not is_finite(world_seconds) or world_seconds < 0.0:
		return "invalid_position"
	if world.is_safe(position.x, position.z):
		return "sheltered"
	if world.is_water(position.x, position.z):
		return "in_water"
	if world.normal_at(position.x, position.z).y < MIN_SLOPE_NORMAL_Y:
		return "bad_terrain"
	var conditions: Dictionary = Weather.conditions(world, position.x, position.z, world_seconds)
	if conditions.is_empty() or bool(conditions.get("sheltered", true)) or (
			str(conditions.get("condition", "")) != "storm"):
		return "no_storm"
	return ""


static func needs_filter(world, position: Vector3) -> bool:
	return world.biome_at(position.x, position.z) == "swamp"


## Full atomic transaction. No payer inputs/output numbers are taken from RPC.
static func transact(inventory: Inventory, polluted: bool) -> Dictionary:
	if inventory.count(TARP_ITEM) < 1:
		return {"ok": false, "reason": "no_tarp"}
	if polluted and inventory.count(FILTER_ITEM) < 1:
		return {"ok": false, "reason": "need_filter"}
	var trial := Inventory.new(inventory.slots.size())
	trial.load_dict(inventory.to_dict())
	if not trial.remove(TARP_ITEM, 1):
		return {"ok": false, "reason": "no_tarp"}
	if polluted and not trial.remove(FILTER_ITEM, 1):
		return {"ok": false, "reason": "need_filter"}
	if trial.add(WATER_ITEM, WATER_COUNT) != 0:
		return {"ok": false, "reason": "no_space"}
	inventory.load_dict(trial.to_dict())
	return {"ok": true, "filtered": polluted, "count": WATER_COUNT}
