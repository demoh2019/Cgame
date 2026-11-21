extends RefCounted
## Binary raster feature distance field, measured in eight-connected pixel steps.
## Cgame uses one linear-time native call; upstream Godot uses an equivalent
## bounded two-pass algorithm with the same result and no GPU dependency.


static func compute(mask: PackedByteArray, size: Vector2i, max_distance: int = 7,
		force_scalar: bool = false) -> PackedByteArray:
	var empty := PackedByteArray()
	if size.x < 1 or size.y < 1 or size.x > 2048 or size.y > 2048 			or max_distance < 0 or max_distance > 254 or mask.size() != size.x * size.y:
		return empty
	if not force_scalar and Geometry2D.has_method("distance_transform_8"):
		var native: PackedByteArray = Geometry2D.call("distance_transform_8", mask, size, max_distance)
		if native.size() == mask.size():
			return native
	var result := PackedByteArray()
	result.resize(mask.size())
	for i in mask.size():
		result[i] = 0 if mask[i] != 0 else 255
	# Forward: W, NW, N, NE.
	for y in size.y:
		for x in size.x:
			var index: int = y * size.x + x
			var best: int = result[index]
			if x > 0:
				best = mini(best, result[index - 1] + 1)
			if y > 0:
				if x > 0:
					best = mini(best, result[index - size.x - 1] + 1)
				best = mini(best, result[index - size.x] + 1)
				if x + 1 < size.x:
					best = mini(best, result[index - size.x + 1] + 1)
			if best <= max_distance:
				result[index] = best
	# Backward: E, SE, S, SW.
	for y in range(size.y - 1, -1, -1):
		for x in range(size.x - 1, -1, -1):
			var index: int = y * size.x + x
			var best: int = result[index]
			if x + 1 < size.x:
				best = mini(best, result[index + 1] + 1)
			if y + 1 < size.y:
				if x + 1 < size.x:
					best = mini(best, result[index + size.x + 1] + 1)
				best = mini(best, result[index + size.x] + 1)
				if x > 0:
					best = mini(best, result[index + size.x - 1] + 1)
			if best <= max_distance:
				result[index] = best
	return result


static func from_heights(heights: PackedFloat32Array, size: Vector2i,
		land_threshold: float, max_distance: int = 7,
		force_scalar: bool = false) -> PackedByteArray:
	if not is_finite(land_threshold) or size.x < 1 or size.y < 1 			or size.x > 2048 or size.y > 2048 or heights.size() != size.x * size.y:
		return PackedByteArray()
	var mask := PackedByteArray()
	mask.resize(heights.size())
	for i in heights.size():
		if not is_finite(heights[i]):
			return PackedByteArray()
		mask[i] = 255 if heights[i] >= land_threshold else 0
	return compute(mask, size, max_distance, force_scalar)
