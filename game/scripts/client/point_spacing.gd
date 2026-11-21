extends RefCounted
## Ordered geometry self-pruning: use Cgame's bounded spatial hash when
## available, otherwise retain exact scalar semantics in stock Godot.


static func keep_indices(points: PackedVector2Array, separation: float,
		max_keep: int = -1, force_scalar: bool = false) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if points.size() > 8192 or not is_finite(separation) or separation < 0.0:
		return empty
	if not is_finite(separation * separation) or max_keep < -1 or max_keep > 8192:
		return empty
	for point in points:
		if not point.is_finite():
			return empty
	if not force_scalar and Geometry2D.has_method("prune_points_min_distance"):
		return Geometry2D.call("prune_points_min_distance", points, separation, max_keep)
	var kept := PackedInt32Array()
	var min_squared: float = separation * separation
	for i in points.size():
		if max_keep >= 0 and kept.size() >= max_keep:
			break
		var allowed := true
		for j in kept:
			if points[i].distance_squared_to(points[j]) < min_squared:
				allowed = false
				break
		if allowed:
			kept.append(i)
	return kept


## Bounded decorative scatter selection: generate more candidates than needed
## and prune once before any mesh creation or height/biome sampling.
static func candidates(rng: RandomNumberGenerator, rect: Rect2, attempts: int,
		separation: float, max_keep: int, force_scalar: bool = false) -> PackedVector2Array:
	var result := PackedVector2Array()
	if rng == null or not rect.position.is_finite() or not rect.size.is_finite():
		return result
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or attempts < 0 or attempts > 8192:
		return result
	if not is_finite(separation) or separation < 0.0 or max_keep < -1 or max_keep > 8192:
		return result
	var points := PackedVector2Array()
	points.resize(attempts)
	for i in attempts:
		points[i] = Vector2(rect.position.x + rng.randf() * rect.size.x,
				rect.position.y + rng.randf() * rect.size.y)
	var indices := keep_indices(points, separation, max_keep, force_scalar)
	result.resize(indices.size())
	for i in indices.size():
		result[i] = points[indices[i]]
	return result
