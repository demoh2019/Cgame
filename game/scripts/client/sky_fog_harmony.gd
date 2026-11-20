extends RefCounted
## Keep fog in the 3D world aligned with the same spectral haze as the sky.
## The custom Godot SkyScatteringLUT supplies only a small CPU Color sample
## at the bounded sky-refresh cadence. This function adds no GPU pass/texture.
##
## The blend matches sky.gdshader's optical-depth composition:
##     shaded_sky = mix(panorama, panorama * transmission + scatter, weight)
## Night and low-end renderers preserve the existing fog appearance.


static func blend(base_horizon: Color, optical: Color, strength: float,
		daylight: float, storm: float) -> Color:
	if strength <= 0.001 or daylight <= 0.025:
		return base_horizon
	# Bad settings should never introduce invalid radiance into the world.
	if not is_finite(strength) or not is_finite(daylight) or not is_finite(storm):
		return base_horizon
	if not is_finite(optical.r) or not is_finite(optical.g) or not is_finite(optical.b) or not is_finite(optical.a):
		return base_horizon
	var weight: float = clampf(strength, 0.0, 1.0) * (1.0 - clampf(storm, 0.0, 1.0) * 0.88)
	var transmission: float = clampf(optical.a, 0.0, 1.0)
	var scattered := Color(maxf(optical.r, 0.0), maxf(optical.g, 0.0), maxf(optical.b, 0.0))
	var physically_lit := Color(
		base_horizon.r * transmission + scattered.r,
		base_horizon.g * transmission + scattered.g,
		base_horizon.b * transmission + scattered.b,
		base_horizon.a)
	return base_horizon.lerp(physically_lit, weight)
