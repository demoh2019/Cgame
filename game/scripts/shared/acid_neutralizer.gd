extends RefCounted
## One-use field chemistry for clearing lingering infected acid.
## The client supplies only the item-use request; the server picks pools.
## Direct spitter impacts and already-applied damage are never reversed.

const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")

const ITEM_ID := "field_alkali_kit"
const RANGE := 5.5
const MAX_CLEARED := 3


## Returns stable, closest-first server IDs; ignores expired/invalid pools.
static func targets(pools: Dictionary, position: Vector3, now: float) -> Array[int]:
	var result: Array[int] = []
	if not position.is_finite() or not is_finite(now):
		return result
	var origin := Vector2(position.x, position.z)
	var candidates: Array[Dictionary] = []
	for id in pools.keys():
		if not (id is int) or int(id) <= 0:
			continue
		var pool: Variant = pools[id]
		if not (pool is Dictionary):
			continue
		if not (pool.has("x") and pool.has("z")):
			continue
		var x: float = float(pool["x"])
		var z: float = float(pool["z"])
		if not (is_finite(x) and is_finite(z)):
			continue
		if AcidSpitter.pool_remaining(pool, now) <= 0.0:
			continue
		var distance_sq: float = origin.distance_squared_to(Vector2(x, z))
		if distance_sq <= RANGE * RANGE:
			candidates.append({"id": int(id), "distance_sq": distance_sq})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var delta: float = float(a["distance_sq"]) - float(b["distance_sq"])
		if absf(delta) > 0.00001:
			return delta < 0.0
		return int(a["id"]) < int(b["id"]))
	for candidate in candidates:
		if result.size() >= MAX_CLEARED:
			break
		result.append(int(candidate["id"]))
	return result
