extends RefCounted
## Hybrid reflection budget: sky radiance remains the off-screen fallback,
## while Forward+ adds SSR contacts to opaque PBR objects at High/Ultra only.
## Transparent water has its own reflection model and does not enter opaque SSR.
## Native SSR roughness-mip filtering changes only on quality/profile switches.
static var _last_roughness_quality: int = -1


static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = rendering_method == "forward_plus" and tier >= 2
	return {
		"enabled": enabled,
		"roughness_quality": (
			RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH if enabled and tier == 3
			else (RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM if enabled
			else RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED)),
		"max_steps": 28 if tier == 2 else (48 if tier == 3 else 16),
		"fade_in": 0.12,
		"fade_out": 2.0 if tier == 2 else 2.5,
		# Tighten intersection depth confidence now that half-resolution
		# reprojection is pixel-centered and no longer smears into neighbors.
		# No extra steps or render targets are required for this improvement.
		"depth_tolerance": 0.24 if tier == 2 else (0.20 if tier == 3 else 0.25),
	}


static func apply(environment: Environment, level: int, rendering_method: String) -> void:
	if environment == null:
		return
	var profile: Dictionary = settings(level, rendering_method)
	# The engine's half-resolution SSR already builds a roughness mip chain.
	# High uses medium filtering; Ultra retains smoother glossy gradients.
	# No extra viewport, reflection probe or full-resolution trace pass.
	var roughness_quality: int = int(profile["roughness_quality"])
	if roughness_quality != _last_roughness_quality:
		RenderingServer.environment_set_ssr_roughness_quality(roughness_quality)
		_last_roughness_quality = roughness_quality
	# Hi-Z rays are now guarded in the native shader; invalid rays yield
	# no SSR so the existing sky/reflection probes fill those pixels.
	# Skip redundant native Environment updates on repeated preset applies.
	var enabled: bool = bool(profile["enabled"])
	if environment.ssr_enabled != enabled:
		environment.ssr_enabled = enabled
	if not enabled:
		return
	var steps: int = int(profile["max_steps"])
	if environment.ssr_max_steps != steps:
		environment.ssr_max_steps = steps
	var fade_in: float = float(profile["fade_in"])
	if not is_equal_approx(environment.ssr_fade_in, fade_in):
		environment.ssr_fade_in = fade_in
	var fade_out: float = float(profile["fade_out"])
	if not is_equal_approx(environment.ssr_fade_out, fade_out):
		environment.ssr_fade_out = fade_out
	var tolerance: float = float(profile["depth_tolerance"])
	if not is_equal_approx(environment.ssr_depth_tolerance, tolerance):
		environment.ssr_depth_tolerance = tolerance
