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
	if not force_scalar:
		if Geometry2D.has_method("max_filter_mask"):
			var native: PackedByteArray = Geometry2D.call(
					"max_filter_mask", mask, size, radius)
			if native.size() == mask.size():
				return native
		return _compute_linear(mask, size, radius)
	return _compute_scalar(mask, size, radius)


## Monotone deque per row/column: O(width * height) even for a 64px brush.
## The native path still wins where available; force_scalar remains an oracle.
static func _compute_linear(mask: PackedByteArray, size: Vector2i,
		radius: int) -> PackedByteArray:
	var width: int = size.x
	var height: int = size.y
	var horizontal := PackedByteArray()
	horizontal.resize(mask.size())
	var result := PackedByteArray()
	result.resize(mask.size())
	var indices := PackedInt32Array()
	indices.resize(maxi(width, height))
	for y in height:
		var head: int = 0
		var tail: int = 0
		var next_right: int = 0
		var row: int = y * width
		for x in width:
			var right: int = mini(width - 1, x + radius)
			while next_right <= right:
				var value: int = mask[row + next_right]
				while tail > head and mask[row + indices[tail - 1]] <= value:
					tail -= 1
				indices[tail] = next_right
				tail += 1
				next_right += 1
			while head < tail and indices[head] < x - radius:
				head += 1
			horizontal[row + x] = mask[row + indices[head]]
	for x in width:
		var head: int = 0
		var tail: int = 0
		var next_bottom: int = 0
		for y in height:
			var bottom: int = mini(height - 1, y + radius)
			while next_bottom <= bottom:
				var value: int = horizontal[next_bottom * width + x]
				while tail > head and horizontal[indices[tail - 1] * width + x] <= value:
					tail -= 1
				indices[tail] = next_bottom
				tail += 1
				next_bottom += 1
			while head < tail and indices[head] < y - radius:
				head += 1
			result[y * width + x] = horizontal[indices[head] * width + x]
	return result


## Slow reference path intentionally kept for deterministic test comparisons.
static func _compute_scalar(mask: PackedByteArray, size: Vector2i,
		radius: int) -> PackedByteArray:
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
