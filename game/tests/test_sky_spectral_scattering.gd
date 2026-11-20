extends RefCounted
## Regression contract: native AgX tonemapping, sky IBL and multi-wavelength
## scattering must remain renderer-aware and disabled on low-end presets.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")

func run(t) -> void:
	t.current = "spectral sky quality budgets"
	var low: Dictionary = VisualProfiles.settings(0)
	var balanced: Dictionary = VisualProfiles.settings(1)
	var high: Dictionary = VisualProfiles.settings(2)
	var ultra: Dictionary = VisualProfiles.settings(3)
	t.eq(low["sky_spectral_scattering"], 0.0, "Performance skips exponential sky optics")
	t.eq(balanced["sky_spectral_scattering"], 0.0, "Balanced skips exponential sky optics")
	t.check(float(high["sky_spectral_scattering"]) > 0.0, "High enables spectral horizon haze")
	t.check(float(ultra["sky_spectral_scattering"]) > float(high["sky_spectral_scattering"])
		and float(ultra["sky_spectral_scattering"]) <= 1.0,
		"Ultra adds stronger but bounded spectral scattering")
	t.check(int(high["sky_radiance"]) >= 128 and int(ultra["sky_radiance"]) >= 256,
		"High/Ultra use detailed sky IBL for PBR highlights")
	t.check(float(ultra["sky_refresh_interval"]) >= 0.35,
		"large Ultra cubemaps cannot refresh on every frame")
	t.current = "sky shader keeps cached radiance safe"
	var sky_shader := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(sky_shader != null, "sky shader loads")
	if sky_shader == null:
		return
	var code: String = sky_shader.code
	t.check(code.contains("uniform float spectral_scattering_strength"),
		"the sky exposes a quality scalar")
	t.check(code.contains("spectral_scattering_strength > 0.001")
		and code.contains("transmittance = exp(-vec3("),
		"expensive spectral calculation is gated by quality and light")
	t.check(code.contains("rayleigh_phase") and code.contains("horizon_airmass"),
		"Rayleigh-like directional fill is height dependent")
	t.check(code.contains("use_cached_radiance && !AT_CUBEMAP_PASS"),
		"cached radiance never samples itself during IBL capture")
	t.check(not code.contains("TIME *") and not code.get_slice("void sky() {", 1).contains("return;"),
		"shader stays update-budgeted and compiles without forbidden early return")
	t.current = "real rendering controller and native RD integration"
	var quality_code: String = (GraphicsQuality as Script).source_code
	t.check(quality_code.contains(
		'atmosphere_profile["sky_spectral_scattering"] = world_profile["sky_spectral_scattering"]'),
		"graphics presets forward spectral optics to the live atmosphere")
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(atmosphere_code.contains('set_shader_parameter("spectral_scattering_strength"'),
		"live atmosphere forwards preset spectral strength")
	t.check(atmosphere_code.contains("Environment.TONE_MAPPER_AGX")
		and atmosphere_code.contains('"forward_plus"')
		and atmosphere_code.contains("_shadow_filter_level >= 2"),
		"AgX is reserved for High/Ultra Forward+ and has ACES fallback")
	t.check(atmosphere_code.contains("Sky.RADIANCE_SIZE_256"),
		"native sky IBL can allocate a 256 cubemap")
	var project_config: String = FileAccess.get_file_as_string("res://project.godot")
	t.check(project_config.contains("reflections/sky_reflections/ggx_samples=48"),
		"native renderer prefilter uses higher GGX quality")
	t.check(project_config.contains("environment/ssil/half_size=true"),
		"Godot project settings use correct, nonduplicated section prefixes")
