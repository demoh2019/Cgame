extends RefCounted
## Premium water wind fetch foam: zero new samplers and cheap renderer gating.

const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "water wind foam quality budgets"
	var last: float = -1.0
	for level in 4:
		var profile: Dictionary = Profiles.settings(level)
		var amount: float = float(profile.get("wind_foam_strength", -1.0))
		t.check(is_finite(amount) and amount >= 0.0 and amount <= 0.5,
			"foam budget is finite and bounded")
		t.check(amount >= last, "detail never falls as graphics tier rises")
		last = amount
	t.near(float(Profiles.settings(0)["wind_foam_strength"]), 0.0,
		0.0001, "Performance skips premium foam")
	t.near(float(Profiles.settings(1)["wind_foam_strength"]), 0.0,
		0.0001, "Balanced skips premium foam")
	t.near(float(Profiles.settings(2)["wind_foam_strength"]), 0.20,
		0.0001, "High has modest streaks")
	t.near(float(Profiles.settings(3)["wind_foam_strength"]), 0.42,
		0.0001, "Ultra has expressive wind streaks")
	t.near(float(Profiles.settings(-9)["wind_foam_strength"]), 0.0,
		0.0001, "invalid low tier clamps")
	t.near(float(Profiles.settings(90)["wind_foam_strength"]), 0.42,
		0.0001, "invalid high tier clamps")

	t.current = "premium ocean shader reuses weather and depth"
	var source_shader := load("res://assets/shaders/water.gdshader") as Shader
	t.check(source_shader != null, "actual game shader loads")
	if source_shader == null:
		return
	var code: String = source_shader.code
	t.check(code.contains("uniform float wind_foam_strength = 0.0;"),
		"premium foam is a material uniform")
	t.check(code.contains("#ifdef WATER_REFRACTION"),
		"optional feature compiles in premium variant only")
	t.check(code.contains("wind_foam_strength > 0.001 && detail_fade > 0.001"),
		"no calculation on low tiers or distant water")
	t.check(code.contains("aa_vegetation_wind.z > 0.22 && thickness > 0.65"),
		"calm or near-shore water skips the new effect")
	t.check(code.contains("float along_wind = dot(p, foam_wind_dir)"),
		"foam follows stable world-space weather direction")
	t.check(code.contains("float across_wind = dot(p,"),
		"foam stripes are broken across wind")
	t.check(code.contains("float advect_phase = along_wind * 2.4"),
		"foam moves with fetch rather than view-space movement")
	t.check(code.contains("float wind_foam = ribbon_mask * (0.3 + 0.7 * crest)"),
		"foam shares analytic wave crest instead of new texture samples")
	t.check(code.contains("foam = clamp(foam + wind_foam, 0.0, 1.0)"),
		"water opacity, roughness and color reuse the existing foam result")
	t.check(code.contains("float foam = 0.0") and
		code.contains("float storm_whitecaps") and
		code.contains("shore_surf_strength > 0.001"),
		"shore foam, storms and shore surf remain operational")
	t.check(not code.contains("wind_foam_tex"),
		"no new GPU texture or allocation required")

	t.current = "runtime Forward+ quality and renderer isolation"
	t.check(not WaterRefraction.enabled(0, "forward_plus") and
		not WaterRefraction.enabled(1, "forward_plus") and
		not WaterRefraction.enabled(3, "gl_compatibility"),
		"nonpremium graphics never compile foam path")
	t.check(WaterRefraction.enabled(2, "forward_plus") and
		WaterRefraction.enabled(3, "forward_plus"),
		"high-end Forward+ uses the cached premium shader")
	var material := ShaderMaterial.new()
	WaterRefraction.apply(material, Profiles.settings(3), 3, "forward_plus")
	t.near(float(material.get_shader_parameter("wind_foam_strength")),
		0.42, 0.0001, "Ultra foam budget reaches live water material")
	t.check(material.shader.code.contains("#define WATER_REFRACTION"),
		"premium variant is selected")
	WaterRefraction.apply(material, Profiles.settings(2), 2, "forward_plus")
	t.near(float(material.get_shader_parameter("wind_foam_strength")),
		0.20, 0.0001, "High foam budget replaces Ultra on quality change")
	WaterRefraction.apply(material, Profiles.settings(0), 0, "forward_plus")
	t.check(material.shader == WaterRefraction.BASE_SHADER,
		"Performance restores low-cost shader variant")
	t.check((GraphicsQuality as Script).source_code.contains("WaterRefraction.apply("),
		"live game graphics preset updates water material")
