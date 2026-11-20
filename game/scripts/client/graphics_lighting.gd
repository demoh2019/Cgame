extends RefCounted
## Renderer-aware lighting budgets for Albion After.
## The same presets drive the online world and local playable preview.
## No gameplay state, world seed, server packets or character saves are affected.

## Forward+ is the only Godot 4 renderer with volumetric fog. Splitting the
## main sun into four cascades improves nearby shadow precision, but costs
## more draw work; reserve it for Ultra and stay at two splits on High.
static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var forward_plus: bool = rendering_method == "forward_plus"
	var cascades: int = 0 if tier == 0 else (4 if tier == 3 else 2)
	return {
		"shadow_cascades": cascades,
		"shadow_blend": tier >= 2,
		"shadow_split_1": 0.12 if tier == 3 else 0.23,
		"shadow_split_2": 0.29,
		"shadow_split_3": 0.54,
		"shadow_blur": 1.0 if tier <= 1 else (1.1 if tier == 2 else 1.25),
		"volumetric_fog": forward_plus and tier == 3,
		"volumetric_fog_length": 78.0,
		"volumetric_fog_density": 0.014,
		"volumetric_fog_anisotropy": 0.42,
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
	if environment != null:
		environment.volumetric_fog_enabled = bool(profile["volumetric_fog"])
		if bool(profile["volumetric_fog"]):
			environment.volumetric_fog_length = float(profile["volumetric_fog_length"])
			environment.volumetric_fog_density = float(profile["volumetric_fog_density"])
			environment.volumetric_fog_anisotropy = float(profile["volumetric_fog_anisotropy"])
			environment.volumetric_fog_albedo = Color(0.79, 0.84, 0.93)
