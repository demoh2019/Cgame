extends RefCounted
## Incremental broadphase for player-built walls, beds and multi-part houses.
## Indexed by footprint (not only centre) so radius/edge queries are exact.
## Queries retain Dictionary insertion order for deterministic movement.

const TILE_SIZE := 16.0
const MAX_ENTRY_TILES := 64
const MAX_QUERY_TILES := 256

var _tiles: Dictionary = {} # Vector2i -> Dictionary of owner keys.
var _occupied: Dictionary = {} # int or String owner key -> Array[Vector2i].
var _oversized: Dictionary = {} # Large buildings are checked on every query.
var _order: Dictionary = {} # Stable insertion sequence for mixed int/String keys.
var _serial: int = 0
var last_candidates: int = 0


func upsert(key: Variant, blocker: Dictionary) -> void:
	var x: float = float(blocker.get("x", NAN))
	var z: float = float(blocker.get("z", NAN))
	var radius: float = float(blocker.get("radius", 0.0))
	if not is_finite(x) or not is_finite(z) or not is_finite(radius) or radius <= 0.0:
		return
	if not _order.has(key):
		_order[key] = _serial
		_serial += 1
	else:
		_unindex(key)
	var from: Vector2i = Vector2i(floori((x - radius) / TILE_SIZE), floori((z - radius) / TILE_SIZE))
	var to: Vector2i = Vector2i(floori((x + radius) / TILE_SIZE), floori((z + radius) / TILE_SIZE))
	var columns: int = to.x - from.x + 1
	var rows: int = to.y - from.y + 1
	# Huge footprints would fan out across thousands of buckets. Keep them
	# in a small global overflow list rather than risking runaway memory.
	if columns <= 0 or rows <= 0 or columns > MAX_ENTRY_TILES or rows > MAX_ENTRY_TILES 			or columns * rows > MAX_ENTRY_TILES:
		_oversized[key] = true
		_occupied[key] = []
		return
	var cells: Array[Vector2i] = []
	for tx in range(from.x, to.x + 1):
		for tz in range(from.y, to.y + 1):
			var cell := Vector2i(tx, tz)
			var bucket: Dictionary = _tiles.get(cell, {})
			bucket[key] = true
			_tiles[cell] = bucket
			cells.append(cell)
	_occupied[key] = cells


func remove(key: Variant) -> void:
	_unindex(key)
	_order.erase(key)


func _unindex(key: Variant) -> void:
	if _occupied.has(key):
		var cells: Array = _occupied[key]
		for cell in cells:
			var bucket: Dictionary = _tiles[cell]
			bucket.erase(key)
			if bucket.is_empty():
				_tiles.erase(cell)
		_occupied.erase(key)
	_oversized.erase(key)


## Broadphase candidates are de-duplicated across overlapping tiles and
## sorted back into the original insertion order before the exact AABB check.
func query(blockers: Dictionary, x: float, z: float, radius: float) -> Array:
	last_candidates = 0
	var result: Array = []
	if not is_finite(x) or not is_finite(z) or not is_finite(radius) or radius < 0.0:
		return result
	# A giant query falls back to an exhaustive pass; avoid walking an
	# unbounded number of tiles on malformed/exceptionally wide requests.
	var from: Vector2i = Vector2i(floori((x - radius) / TILE_SIZE), floori((z - radius) / TILE_SIZE))
	var to: Vector2i = Vector2i(floori((x + radius) / TILE_SIZE), floori((z + radius) / TILE_SIZE))
	var columns: int = to.x - from.x + 1
	var rows: int = to.y - from.y + 1
	if blockers.size() != _order.size() or columns <= 0 or rows <= 0 			or columns > MAX_QUERY_TILES or rows > MAX_QUERY_TILES 			or columns * rows > MAX_QUERY_TILES:
		return _scan_all(blockers, x, z, radius)
	var candidates: Dictionary = _oversized.duplicate()
	for tx in range(from.x, to.x + 1):
		for tz in range(from.y, to.y + 1):
			var bucket: Dictionary = _tiles.get(Vector2i(tx, tz), {})
			for key in bucket:
				candidates[key] = true
	var keys: Array = candidates.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(_order[a]) < int(_order[b]))
	last_candidates = keys.size()
	for key in keys:
		if not blockers.has(key):
			continue
		var blocker: Dictionary = blockers[key]
		var reach: float = radius + float(blocker["radius"])
		if absf(float(blocker["x"]) - x) <= reach and absf(float(blocker["z"]) - z) <= reach:
			result.append(blocker)
	return result


func _scan_all(blockers: Dictionary, x: float, z: float, radius: float) -> Array:
	var result: Array = []
	last_candidates = blockers.size()
	for blocker in blockers.values():
		var reach: float = radius + float(blocker["radius"])
		if absf(float(blocker["x"]) - x) <= reach and absf(float(blocker["z"]) - z) <= reach:
			result.append(blocker)
	return result


## Constant-time diagnostics, including the previous movement query's cost.
func stats() -> Dictionary:
	return {"entries": _order.size(), "tiles": _tiles.size(),
		"oversized": _oversized.size(), "last_candidates": last_candidates}
