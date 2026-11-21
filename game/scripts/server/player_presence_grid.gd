extends RefCounted
## CPU-side spatial broadphase for server-owned living survivor positions.
## Rebuilt once per infected population maintenance pass (~1 second).
## Preserves exact XZ distance semantics; no client data or scene nodes.

const CELL_SIZE: float = 64.0
const DIRECT_SCAN_THRESHOLD: int = 8
const MAX_HASH_QUERY_RADIUS: float = 512.0 # Large generic queries fall back to exact scan.

var _positions: Array[Vector2] = []
var _cells: Dictionary = {} # Vector2i -> Array[Vector2]
var query_count: int = 0
var batch_calls: int = 0
var candidate_checks: int = 0
var bucket_lookups: int = 0


func rebuild(positions: Array[Vector2]) -> void:
	_positions.clear()
	_cells.clear()
	query_count = 0
	batch_calls = 0
	candidate_checks = 0
	bucket_lookups = 0
	for point in positions:
		if point.is_finite():
			_positions.append(point)
	# Small sessions need no buckets at all. Rebuild from fresh server state
	# once per maintenance pass, so teleports/disconnects never go stale.
	if _positions.size() <= DIRECT_SCAN_THRESHOLD:
		return
	for point in _positions:
		var key: Vector2i = cell_of(point)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(point)


## Exactly matches a brute-force radius check: 'strict' is used for the
## no-spawn radius (<12m); inclusive is used for retention (<=130m).
## The direct path saves hashing overhead on solo and small co-op servers.
func any_within(point: Vector2, radius: float, inclusive: bool = true) -> bool:
	if not point.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	query_count += 1
	var radius_squared: float = radius * radius
	if _positions.size() <= DIRECT_SCAN_THRESHOLD or radius > MAX_HASH_QUERY_RADIUS:
		for player_position in _positions:
			candidate_checks += 1
			var d: float = point.distance_squared_to(player_position)
			if (inclusive and d <= radius_squared) or (not inclusive and d < radius_squared):
				return true
		return false
	var lower: Vector2i = cell_of(point - Vector2.ONE * radius)
	var upper: Vector2i = cell_of(point + Vector2.ONE * radius)
	for z in range(lower.y, upper.y + 1):
		for x in range(lower.x, upper.x + 1):
			bucket_lookups += 1
			var nearby: Array = _cells.get(Vector2i(x, z), [])
			for player_position in nearby:
				candidate_checks += 1
				var distance_squared: float = point.distance_squared_to(player_position)
				if (inclusive and distance_squared <= radius_squared) or (not inclusive and distance_squared < radius_squared):
					return true
	return false


## Return one flag per probe, in input order. Invalid points count as misses.
## Query/candidate diagnostics follow scalar semantics for reproducible tests.
func any_within_batch(points: PackedVector2Array, radius: float,
		inclusive: bool = true) -> PackedByteArray:
	batch_calls += 1
	var flags := PackedByteArray()
	flags.resize(points.size())
	for i in range(points.size()):
		flags[i] = 1 if any_within(points[i], radius, inclusive) else 0
	return flags


func snapshot() -> Dictionary:
	return {
		"alive_players": _positions.size(),
		"occupied_cells": _cells.size(),
		"queries": query_count,
		"batch_calls": batch_calls,
		"candidate_checks": candidate_checks,
		"bucket_lookups": bucket_lookups,
		"indexed_mode": _positions.size() > DIRECT_SCAN_THRESHOLD
	}


static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
