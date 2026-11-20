extends RefCounted
## Hybrid reflection budget: sky radiance remains the off-screen fallback,
## while Forward+ adds SSR contacts to opaque PBR objects at High/Ultra only.
## Transparent water has its own reflection model and does not enter opaque SSR.

static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	return {
		"enabled": rendering_method == "forward_plus" and tier >= 2,
		"max_steps": 28 if tier == 2 else (48 if tier == 3 else 16),
		"fade_in": 0.12,
		"fade_out": 2.0 if tier == 2 else 2.5,
		"depth_tolerance": 0.25 if tier == 2 else 0.22,
	}


static func apply(environment: Environment, level: int, rendering_method: String) -> void:
	if environment == null:
		return
	var profile: Dictionary = settings(level, rendering_method)
	# Clear the prior setting on renderer fallback or when Auto chooses a cheaper tier.
	environment.ssr_enabled = bool(profile["enabled"])
	if not environment.ssr_enabled:
		return
	environment.ssr_max_steps = int(profile["max_steps"])
	environment.ssr_fade_in = float(profile["fade_in"])
	environment.ssr_fade_out = float(profile["fade_out"])
	environment.ssr_depth_tolerance = float(profile["depth_tolerance"])
