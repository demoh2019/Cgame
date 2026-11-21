extends RefCounted
## Grayscale square maximum filter / Chebyshev dilation, for procedural
## vegetation exclusion. Cgame's O(N) native two-pass implementation is used
## where available; stock Godot has a separable GDScript fallback.


static func compute(mask: PackedByteArray, size: Vector2i, radius: int = 2,
		force_scalar: bool = false) -> PackedByteArray:
	var empty := PackedByteArray()
	if size.x < 1 or size.y < 1 or size.x > 2048 or size.y > 2048:
		return empty
	if radius < 0 or radius > 64 or mask.size() != size.x * size.y:
		return empty
	if radius == 0:
		return mask.duplicate()
	if not force_scalar and Geometry2D.has_method("max_filter_mask"):
		var native: PackedByteArray = Geometry2D.call(
				"max_filter_mask", mask, size, radius)
		if native.size() == mask.size():
			return native
	var horizontal := PackedByteArray()
	horizontal.resize(mask.size())
	var result := PackedByteArray()
	result.resize(mask.size())
	# The fallback is separable, with an O(radius) scan per axis; on the
	# 64x64 road texture radius is only two pixels.
	for y in size.y:
		for x in size.x:
			var maximum: int = 0
			for sx in range(maxi(0, x - radius), mini(size.x - 1, x + radius) + 1):
				maximum = maxi(maximum, mask[y * size.x + sx])
			horizontal[y * size.x + x] = maximum
	for x in size.x:
		for y in size.y:
			var maximum: int = 0
			for sy in range(maxi(0, y - radius), mini(size.y - 1, y + radius) + 1):
				maximum = maxi(maximum, horizontal[sy * size.x + x])
			result[y * size.x + x] = maximum
	return result
