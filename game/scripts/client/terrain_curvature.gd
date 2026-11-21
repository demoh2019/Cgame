extends RefCounted
## Seam-continuous cavity/ridge vertex color baking. The engine receives a
## one-sample height halo, ensuring neighbors across streamed chunks match.
## The CPU bake runs once per chunk; stock Godot retains scalar parity.

const CAVITY_START := 0.015
const CAVITY_END := 0.32
const RIDGE_START := 0.015
const RIDGE_END := 0.42


## R = concave cavity, G = convex ridge, B = baked open sky, A = opaque.
## A shared height sampler is called only for the four edge strips.
static func build(heights: PackedFloat32Array, origin: Vector2,
		side: int, spacing: float, world_height: Callable,
		force_scalar: bool = false) -> PackedColorArray:
	var empty := PackedColorArray()
	if side < 2 or side > 2046 or not origin.is_finite():
		return empty
	if not is_finite(spacing) or spacing <= 0.0 or not world_height.is_valid():
		return empty
	if heights.size() != side * side:
		return empty
	var inv_spacing_squared: float = (1.0 / spacing) * (1.0 / spacing)
	if not is_finite(inv_spacing_squared) or inv_spacing_squared <= 0.0:
		return empty
	var padded_side: int = side + 2
	var padded := PackedFloat32Array()
	padded.resize(padded_side * padded_side)
	for z in side:
		for x in side:
			padded[(z + 1) * padded_side + x + 1] = heights[z * side + x]
	# Sample outside the chunk only along each edge, not the corners.
	for z in side:
		var wz: float = origin.y + float(z) * spacing
		padded[(z + 1) * padded_side] = float(world_height.call(origin.x - spacing, wz))
		padded[(z + 1) * padded_side + side + 1] = float(
				world_height.call(origin.x + float(side) * spacing, wz))
	for x in side:
		var wx: float = origin.x + float(x) * spacing
		padded[x + 1] = float(world_height.call(wx, origin.y - spacing))
		padded[(side + 1) * padded_side + x + 1] = float(
				world_height.call(wx, origin.y + float(side) * spacing))
	for h in padded:
		if not is_finite(h):
			return empty
	if not force_scalar and Geometry2D.has_method("bake_heightfield_curvature_colors"):
		var native: PackedColorArray = Geometry2D.call(
				"bake_heightfield_curvature_colors", padded, Vector2i(side, side),
				spacing, CAVITY_START, CAVITY_END, RIDGE_START, RIDGE_END)
		if native.size() == side * side:
			return native
	var colors := PackedColorArray()
	colors.resize(side * side)
	for z in side:
		for x in side:
			var i: int = (z + 1) * padded_side + x + 1
			var curvature: float = (float(padded[i - 1]) + float(padded[i + 1])
					+ float(padded[i - padded_side]) + float(padded[i + padded_side])
					- 4.0 * float(padded[i])) * inv_spacing_squared
			if not is_finite(curvature):
				return empty
			var cavity: float = smoothstep(CAVITY_START, CAVITY_END, maxf(0.0, curvature))
			var ridge: float = smoothstep(RIDGE_START, RIDGE_END, maxf(0.0, -curvature))
			colors[z * side + x] = Color(cavity, ridge, 1.0, 1.0)
	return colors
