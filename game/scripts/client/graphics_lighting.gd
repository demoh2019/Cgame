extends RefCounted

const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")
## Renderer-aware lighting budgets for Albion After.
## The same presets drive the online world and local playable preview.
## No gameplay state, world seed, server packets or character saves are affected.

## Forward+ is the only Godot 4 renderer with volumetric fog. Splitting the
## main sun into four cascades improves nearby shadow precision, but costs
## more draw work; reserve it for Ultra and stay at two splits on High.
static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var fog: Dictionary = CinematicFog.profile(tier, rendering_method)
	var cascades: int = 0 if tier == 0 else (4 if tier == 3 else 2)
	return {
		"shadow_cascades": cascades,
		"shadow_blend": tier >= 2,
		"shadow_split_1": 0.12 if tier == 3 else 0.23,
		"shadow_split_2": 0.29,
		"shadow_split_3": 0.54,
		"shadow_blur": 1.0 if tier <= 1 else (1.1 if tier == 2 else 1.25),
		"volumetric_fog": bool(fog["enabled"]),
		"volumetric_fog_length": float(fog["length"]),
		"volumetric_fog_density": float(fog["base_density"]),
		"volumetric_fog_anisotropy": 0.38,
		# HDRP-style reflection fidelity budget: short half-resolution rays on
		# High, longer rays on Ultra. Sky reflections remain the fallback.
		"ssr_enabled": rendering_method == "forward_plus" and tier >= 2,
		"ssr_max_steps": 24 if tier == 2 else (48 if tier == 3 else 0),
		"ssr_fade_in": 0.14,
		"ssr_fade_out": 1.8,
		"ssr_depth_tolerance": 0.20,
	}


## A single apply point keeps shadow settings consistent with the actual
## backend, including after the user changes presets at runtime.
static func apply(sun: DirectionalLight3D, environment: Environment,
		level: int, rendering_method: String) -> void:
	var profile: Dictionary = settings(level, rendering_method)
	if sun != null:
		if int(profile["shadow_cascades"]) == 4:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		elif int(profile["shadow_cascades"]) == 2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		else:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_blend_splits = bool(profile["shadow_blend"])
		sun.directional_shadow_split_1 = float(profile["shadow_split_1"])
		sun.directional_shadow_split_2 = float(profile["shadow_split_2"])
		sun.directional_shadow_split_3 = float(profile["shadow_split_3"])
		sun.shadow_blur = float(profile["shadow_blur"])
	# The same atmospheric model is used by this quality selector and by
	# the day/night weather rig. No second, conflicting fog controller.
	CinematicFog.apply_profile(environment, sun,
		CinematicFog.profile(level, rendering_method))
	if environment != null:
		# Screen-space reflections require Forward+; setting them only at
		# quality changes avoids per-frame renderer reconfiguration.
		environment.ssr_enabled = bool(profile["ssr_enabled"])
		if environment.ssr_enabled:
			environment.ssr_max_steps = int(profile["ssr_max_steps"])
			environment.ssr_fade_in = float(profile["ssr_fade_in"])
			environment.ssr_fade_out = float(profile["ssr_fade_out"])
			environment.ssr_depth_tolerance = float(profile["ssr_depth_tolerance"])
