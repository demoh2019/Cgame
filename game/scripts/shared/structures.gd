extends RefCounted
## Rules for a bounded, session-local defensive structure in the authoritative world.
## 2D circular obstacle collision is shared by survivors and infected.
## Visual/physics bodies may be created by clients but never decide durability.

const COST := {"wood_1": 4, "stone_1": 2}
const REPAIR_COST := {"wood_1": 1}
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
