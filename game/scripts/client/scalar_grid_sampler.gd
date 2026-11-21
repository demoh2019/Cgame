extends RefCounted
## Wrapped lattice-grid sampler for PCG texture fields, clouds and weather.
## Native Cgame interpolates all UV queries in one call. Standard Godot
## uses the same two-axis periodic interpolation in GDScript.


static func sample_wrapped(grid: PackedFloat32Array, size: Vector2i,
		uvs: PackedVector2Array, smooth: bool = true,
		force_scalar: bool = false) -> PackedFloat32Array:
	var empty := PackedFloat32Array()
	if size.x < 1 or size.y < 1 or size.x > 2048 or size.y > 2048 			or grid.size() != size.x * size.y or uvs.size() > 65536:
		return empty
	for value in grid:
		if not is_finite(value):
			return empty
	for uv in uvs:
		if not uv.is_finite():
			return empty
	if not force_scalar and Geometry2D.has_method("sample_scalar_grid_wrapped"):
		var native: PackedFloat32Array = Geometry2D.call(
				"sample_scalar_grid_wrapped", grid, size, uvs, smooth)
		if native.size() == uvs.size():
			return native
	var output := PackedFloat32Array()
	output.resize(uvs.size())
	for i in uvs.size():
		var px: float = fposmod(uvs[i].x, 1.0) * float(size.x)
		var py: float = fposmod(uvs[i].y, 1.0) * float(size.y)
		var x0: int = clampi(floori(px), 0, size.x - 1)
		var y0: int = clampi(floori(py), 0, size.y - 1)
		var x1: int = (x0 + 1) % size.x
		var y1: int = (y0 + 1) % size.y
		var fx: float = px - float(x0)
		var fy: float = py - float(y0)
		if smooth:
			fx = fx * fx * (3.0 - 2.0 * fx)
			fy = fy * fy * (3.0 - 2.0 * fy)
		var a: float = lerpf(grid[y0 * size.x + x0], grid[y0 * size.x + x1], fx)
		var b: float = lerpf(grid[y1 * size.x + x0], grid[y1 * size.x + x1], fx)
		var value: float = lerpf(a, b, fy)
		if not is_finite(value):
			return empty
		output[i] = value
	return output
