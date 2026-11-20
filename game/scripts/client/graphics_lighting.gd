extends RefCounted

const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")
const PracticalShadowCascades = preload("res://scripts/client/practical_shadow_cascades.gd")
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
		# Larger High/Ultra shadow atlases resolve more depth precision.
		# Reduce light separation gently to tighten contact at feet, trunks
		# and building foundations without altering cascade coverage.
		"shadow_bias": 0.04 if tier <= 1 else (0.034 if tier == 2 else 0.028),
		"shadow_normal_bias": 1.2 if tier <= 1 else (1.0 if tier == 2 else 0.82),
		# HDRP-like short-range contact shadows resolve small gaps at feet,
		# stones and tree roots where cascaded shadow maps lose detail. They
		# cost one native depth-based ray trace, so only premium Forward+ tiers.
		"contact_shadows": rendering_method == "forward_plus" and tier >= 2,
		"contact_shadow_blur": 0.9 if tier <= 2 else 0.55,
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
		# HDRP-style practical CSM allocation: preserve the atlas budget
		# and existing 2/4 cascade count, concentrate texels on nearby
		# player/foliage/ruin silhouettes. Engine validates and quantizes
		# split distances so repeated quality updates are idempotent.
		if not PracticalShadowCascades.try_apply(sun, level, rendering_method):
			# Stock Godot, low-end backends and invalid plans keep the
			# original authored split fractions without any new native API.
			sun.directional_shadow_split_1 = float(profile["shadow_split_1"])
			sun.directional_shadow_split_2 = float(profile["shadow_split_2"])
			sun.directional_shadow_split_3 = float(profile["shadow_split_3"])
		sun.shadow_blur = float(profile["shadow_blur"])
		sun.shadow_bias = float(profile["shadow_bias"])
		sun.shadow_normal_bias = float(profile["shadow_normal_bias"])
		# The world uses one directional sun. Do not allocate a contact
		# shadow pass for Performance/Balanced, Mobile or Compatibility.
		# Live renderer changes also clear the previously enabled flag.
		var contacts_enabled: bool = bool(profile["contact_shadows"])
		if contacts_enabled:
			sun.shadow_contact_shadows_blur = float(profile["contact_shadow_blur"])
		sun.shadow_contact_shadows_allow = contacts_enabled
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
