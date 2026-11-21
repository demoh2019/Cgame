extends RefCounted
## Read-only row-major heightfield gradients for cartographic hillshade and
## procedural terrain slope masks. The fork provides a native batch; stock
## Godot uses the same clamped-edge central differences in GDScript.


static func compute(heights: PackedFloat32Array, size: Vector2i, spacing: float,
		force_scalar: bool = false) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if size.x < 1 or size.y < 1 or size.x > 2048 or size.y > 2048:
		return empty
	if heights.size() != size.x * size.y or not is_finite(spacing) or spacing <= 0.0:
		return empty
	var half_inverse_spacing: float = 0.5 / spacing
	if not is_finite(half_inverse_spacing):
		return empty
	for h in heights:
		if not is_finite(h):
			return empty
	if not force_scalar and Geometry2D.has_method("heightfield_gradients"):
		var native: PackedVector2Array = Geometry2D.call(
				"heightfield_gradients", heights, size, spacing)
		if native.size() == heights.size():
			return native
	var slopes := PackedVector2Array()
	slopes.resize(heights.size())
	for y in size.y:
		var above: int = maxi(y - 1, 0) * size.x
		var below: int = mini(y + 1, size.y - 1) * size.x
		var row: int = y * size.x
		for x in size.x:
			var west: int = maxi(x - 1, 0)
			var east: int = mini(x + 1, size.x - 1)
			var derivative := Vector2(
					(float(heights[row + east]) - float(heights[row + west])) * half_inverse_spacing,
					(float(heights[below + x]) - float(heights[above + x])) * half_inverse_spacing)
			if not derivative.is_finite():
				return empty
			slopes[row + x] = derivative
	return slopes


static func surface_normal(gradient: Vector2) -> Vector3:
	if not gradient.is_finite():
		return Vector3.UP
	return Vector3(-gradient.x, 1.0, -gradient.y).normalized()
