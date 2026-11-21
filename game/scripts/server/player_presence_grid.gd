extends RefCounted
## CPU-side spatial broadphase for server-owned living survivor positions.
## Rebuilt once per infected population maintenance pass (~1 second).
## Preserves exact XZ distance semantics; no client data or scene nodes.

const CELL_SIZE: float = 64.0
const DIRECT_SCAN_THRESHOLD: int = 8

var _positions: Array[Vector2] = []
var _cells: Dictionary = {} # Vector2i -> Array[Vector2]
var query_count: int = 0
var candidate_checks: int = 0
var bucket_lookups: int = 0


func rebuild(positions: Array[Vector2]) -> void:
	_positions.clear()
	_cells.clear()
	query_count = 0
	candidate_checks = 0
	bucket_lookups = 0
	for point in positions:
		if not point.is_finite():
			continue
		_positions.append(point)
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
	if _positions.size() <= DIRECT_SCAN_THRESHOLD:
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


func snapshot() -> Dictionary:
	return {
		"alive_players": _positions.size(),
		"occupied_cells": _cells.size(),
		"queries": query_count,
		"candidate_checks": candidate_checks,
		"bucket_lookups": bucket_lookups,
		"indexed_mode": _positions.size() > DIRECT_SCAN_THRESHOLD
	}


static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
