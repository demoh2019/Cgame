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


static func salvage_for_health(hp: float) -> Dictionary:
	if not is_finite(hp) or hp <= 0.0:
		return {}
	return SALVAGE_GOOD.duplicate() if hp >= MAX_HEALTH * 0.5 else SALVAGE_DAMAGED.duplicate()


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
		"owner": int(data["owner"]),
	}
