extends RefCounted
## Fixed-pixel atmospheric particle footprints. Perspective world size scales
## with camera depth; orthographic size is constant. Pure fallback for stock
## Godot, whose Camera3D has no native world-size projection helper.
##
## Unreal TSR's thin-feature discussion motivates avoiding huge subpixel-to-
## multpixel shifts; this does NOT implement temporal reconstruction or TSR.

const MIN_WORLD_DIAMETER := 0.012
const MAX_WORLD_DIAMETER := 0.40


static func target_pixels(level: int, render_scale: float = 1.0) -> float:
	var tier := clampi(level, 0, 3)
	var pixels: float = [0.0, 3.0, 3.5, 4.0][tier]
	if pixels <= 0.0:
		return 0.0
	var scale := clampf(render_scale if is_finite(render_scale) else 1.0, 0.5, 1.0)
	# At least 1.75 pixels in the *internal* 3D buffer for FSR2.
	return maxf(pixels, 1.75 / scale)


static func safe_diameter(world_size: float) -> float:
	if not is_finite(world_size) or world_size <= 0.0:
		return 0.0
	return clampf(world_size, MIN_WORLD_DIAMETER, MAX_WORLD_DIAMETER)


## Exact for perspective FOV and orthogonal camera with either keep-aspect
## mode. For an asymmetric frustum stock Godot uses this conservative estimate.
static func fallback_world_diameter(target: float, viewport: Vector2,
		fov_deg: float, orthogonal_size: float, keep_width: bool,
		orthogonal: bool, depth: float) -> float:
	if target <= 0.0 or not is_finite(target) or viewport.x <= 0.0 or viewport.y <= 0.0:
		return 0.0
	var axis_pixels: float = viewport.x if keep_width else viewport.y
	var density: float = 0.0
	if orthogonal:
		if not is_finite(orthogonal_size) or orthogonal_size <= 0.0:
			return 0.0
		density = axis_pixels / orthogonal_size
	else:
		if not is_finite(fov_deg) or fov_deg <= 0.0 or fov_deg >= 179.0:
			return 0.0
		if not is_finite(depth) or depth <= 0.0:
			return 0.0
		density = axis_pixels / (2.0 * tan(deg_to_rad(fov_deg) * 0.5) * depth)
	return safe_diameter(target / maxf(density, 0.0001))
