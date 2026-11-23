extends RefCounted
## Stock/older-engine fallback for the native nearest-neighbor broadphase.
## Indices are sorted by distance then original index to select a bounded
## cohort; output is again sorted by index to keep server alert order stable.


static func choose(positions: PackedVector2Array, source_index: int,
		candidates: Array[int], radius: float, max_neighbors: int) -> PackedInt32Array:
	var picked := PackedInt32Array()
	if source_index < 0 or source_index >= positions.size() \
			or max_neighbors < 1 or max_neighbors > 64 \
			or not is_finite(radius) or radius < 0.0 or radius > 256.0:
		return picked
	var origin: Vector2 = positions[source_index]
	if not origin.is_finite():
		return picked
	var ranked: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index in candidates:
		if index < 0 or index >= positions.size():
			return PackedInt32Array()
		if index == source_index or seen.has(index):
			continue
		var point: Vector2 = positions[index]
		if not point.is_finite():
			return PackedInt32Array()
		seen[index] = true
		var distance_squared: float = origin.distance_squared_to(point)
		if distance_squared <= radius * radius:
			ranked.append({"index": index, "distance_squared": distance_squared})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = float(a["distance_squared"])
		var db: float = float(b["distance_squared"])
		return da < db or (da == db and int(a["index"]) < int(b["index"]))
	)
	var selected: Array[int] = []
	for i in range(mini(max_neighbors, ranked.size())):
		selected.append(int(ranked[i]["index"]))
	selected.sort()
	for index in selected:
		picked.append(index)
	return picked
