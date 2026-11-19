extends RefCounted
## Rules for a bounded, session-local defensive structure in the authoritative world.
## 2D circular obstacle collision is shared by survivors and infected.
## Visual/physics bodies may be created by clients but never decide durability.

const COST := {"wood_1": 4, "stone_1": 2}
const REPAIR_COST := {"wood_1": 1}
# Dismantling recovers fewer materials than building costs, never profitable.
const SALVAGE_GOOD := {"wood_1": 2, "stone_1": 1}
const SALVAGE_DAMAGED := {"wood_1": 1}
const DISMANTLE_RANGE := 3.0
const MAX_HEALTH := 120.0
# T1-T4 defenses use original resources and crafted/refined materials.
# Each upgrade consumes one transaction on the server, then raises max HP.
const MAX_TIER := 4
const MAX_HEALTH_BY_TIER := [0.0, 120.0, 240.0, 400.0, 600.0]
const DAMAGE_FACTOR_BY_TIER := [0.0, 1.0, 0.82, 0.66, 0.5]
const REPAIR_AMOUNT_BY_TIER := [0.0, 40.0, 60.0, 85.0, 110.0]
const UPGRADE_COST_BY_TIER := {
	2: {"plank_2": 4, "stone_2": 2},
	3: {"plank_3": 4, "bar_3": 3},
	4: {"plank_4": 6, "bar_4": 4},
}
const REPAIR_COST_BY_TIER := {
	1: {"wood_1": 1},
	2: {"plank_2": 1},
	3: {"bar_3": 1},
	4: {"bar_4": 1},
}
const UPGRADE_RANGE := 3.0


static func tier_of(data: Dictionary) -> int:
	# Old saved and session walls without a tier are T1 by definition.
	return int(data.get("tier", 1))


static func valid_tier(tier: int) -> bool:
	return tier >= 1 and tier <= MAX_TIER


static func max_health(tier: int) -> float:
	return MAX_HEALTH_BY_TIER[tier] if valid_tier(tier) else 0.0


static func upgrade_cost(tier: int) -> Dictionary:
	return UPGRADE_COST_BY_TIER.get(tier, {}).duplicate()


static func repair_cost(tier: int) -> Dictionary:
	return REPAIR_COST_BY_TIER.get(tier, {}).duplicate()


static func repair_amount(tier: int) -> float:
	return REPAIR_AMOUNT_BY_TIER[tier] if valid_tier(tier) else 0.0


static func damage_factor(tier: int) -> float:
	return DAMAGE_FACTOR_BY_TIER[tier] if valid_tier(tier) else 1.0
const REPAIR_HEALTH := 40.0
const RADIUS := 0.85
const BUILD_RANGE := 4.0
const MIN_BUILD_DISTANCE := 1.7
const REPAIR_RANGE := 3.0
const MIN_HUB_DISTANCE := 50.0
const MAX_PER_OWNER := 12
const MAX_GLOBAL := 300
const MIN_SLOPE_NORMAL_Y := 0.78
const ZOMBIE_REACH := 1.75


## Authenticated owners keep management rights after reconnecting with a new peer ID.
## Guest structures intentionally remain session/peer owned until accounts exist.
static func can_manage(data: Dictionary, peer_id: int, user_id: String) -> bool:
	var account: String = str(data.get("owner_account", ""))
	if account != "":
		return user_id != "" and account == user_id
	return int(data.get("owner", -1)) == peer_id


static func salvage_for_health(hp: float, tier: int = 1) -> Dictionary:
	if not is_finite(hp) or hp <= 0.0 or not valid_tier(tier):
		return {}
	# Only T1 base building materials are recovered; expensive upgraded
	# materials are deliberately sunk, so dismantling cannot mint rare goods.
	return SALVAGE_GOOD.duplicate() if hp >= max_health(tier) * 0.5 else SALVAGE_DAMAGED.duplicate()


static func within_range(a: Vector2, b: Vector2, limit: float) -> bool:
	return a.is_finite() and b.is_finite() and a.distance_squared_to(b) <= limit * limit


static func public_state(data: Dictionary) -> Dictionary:
	# Never expose a user's account ID or backend identity in world snapshots.
	return {
		"id": int(data["id"]),
		"x": float(data["x"]),
		"y": float(data["y"]),
		"z": float(data["z"]),
		"hp": float(data["hp"]),
		"tier": tier_of(data), "max_hp": max_health(tier_of(data)),
		"owner": int(data["owner"]),
	}
