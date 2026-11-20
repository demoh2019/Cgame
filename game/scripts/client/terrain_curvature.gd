extends RefCounted
## Height-derived, seam-continuous cavity/ridge vertex colors.
## Sample the authoritative world height only at the outer ring; all interior
## neighbors come from the existing terrain samples. There is no per-frame
## work, no extra texture, and identical edge colors at neighboring chunks.


## R = concave cavity (indirect shade), G = convex ridge (soft warm lift).
## The material still owns the actual sun shadows, clouds, PBR and roughness.
static func build(heights: PackedFloat32Array, origin: Vector2,
		side: int, spacing: float, world_height: Callable) -> PackedColorArray:
	var colors := PackedColorArray()
	if side < 2 or not is_finite(spacing) or spacing <= 0.0 			or heights.size() != side * side or not world_height.is_valid():
		return colors
	colors.resize(side * side)
	var inv_spacing_squared: float = 1.0 / (spacing * spacing)
	for z in side:
		var wz: float = origin.y + float(z) * spacing
		for x in side:
			var wx: float = origin.x + float(x) * spacing
			var index: int = z * side + x
			var center: float = heights[index]
			var left: float = heights[index - 1] if x > 0 else float(
					world_height.call(wx - spacing, wz))
			var right: float = heights[index + 1] if x < side - 1 else float(
					world_height.call(wx + spacing, wz))
			var near: float = heights[index - side] if z > 0 else float(
					world_height.call(wx, wz - spacing))
			var far: float = heights[index + side] if z < side - 1 else float(
					world_height.call(wx, wz + spacing))
			# Discrete Laplacian, measured in world-height units per m^2.
			# Positive means a small valley, negative a convex hilltop.
			var curvature: float = (left + right + near + far - 4.0 * center) 					* inv_spacing_squared
			var cavity: float = smoothstep(0.015, 0.32, maxf(0.0, curvature))
			var ridge: float = smoothstep(0.015, 0.42, maxf(0.0, -curvature))
			colors[index] = Color(cavity, ridge, 0.0, 1.0)
	return colors
