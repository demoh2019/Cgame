extends RefCounted
## The sunny ocean should pick up premium wave highlights without
## recompiling low-end shaders, adding texture reads or breaking refraction.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "sun glitter is tied to the actual High and Ultra GPU budget"
	var values: Array[float] = [0.0, 0.0, 0.38, 0.80]
	var old: float = -1.0
	for tier in 4:
		var p: Dictionary = VisualProfiles.settings(tier)
		var strength: float = float(p["sun_glitter_strength"])
		t.near(strength, values[tier], 0.000001,
			"sun glint matches the explicit per-preset rendering budget")
		t.check(strength >= old and strength <= 1.0,
			"glint quality is monotonic, finite and bounded")
		old = strength
	t.eq(VisualProfiles.settings(0)["sun_glitter_strength"], 0.0,
		"Performance avoids all solar sparkle shading")
	t.eq(VisualProfiles.settings(1)["sun_glitter_strength"], 0.0,
		"Balanced keeps its previous low-end pixel cost")
	var copy: Dictionary = VisualProfiles.settings(3)
	copy["sun_glitter_strength"] = 0.0
	t.check(float(VisualProfiles.settings(3)["sun_glitter_strength"]) > 0.5,
		"mutating a runtime preset cannot corrupt the cached Ultra budget")

	t.current = "no new shader variant or GPU rendering pass is introduced"
	var low: Shader = WaterRefraction.shader_for(1, "forward_plus")
	var ultra: Shader = WaterRefraction.shader_for(3, "forward_plus")
	var high: Shader = WaterRefraction.shader_for(2, "forward_plus")
	t.check(high == ultra,
		"High and Ultra share the same precompiled premium shader variant")
	t.check(low != high,
		"low-end compilation continues to omit premium wave programs")
	t.eq(WaterRefraction.shader_for(3, "gl_compatibility"), low,
		"Compatibility never activates the premium glitter shader")
	t.eq(WaterRefraction.shader_for(3, "mobile"), low,
		"Mobile uses the lightweight water variant")
	t.check(ultra.code.contains("#define WATER_REFRACTION") and
		ultra.code.contains("sun_glitter_strength"),
		"the new effect is compiled only in the existing premium variant")

	t.current = "sun reflections use real world-space animated wave normals"
	var src: String = FileAccess.get_file_as_string(
		"res://assets/shaders/water.gdshader")
	t.check(src.contains("wave_world_normal = world_normal"),
		"specular alignment reuses the existing wave normal and wind movement")
	t.check(src.contains("reflect(-normalize(aa_sun_to_light), wave_world_normal)"),
		"glints reflect the real directional sun, not a fixed fake light")
	t.check(src.contains("aa_sun_radiance * glint"),
		"sun spectrum and energy from the sky tint the water glint")
	t.check(src.contains("detail_fade > 0.001") and
		src.contains("foam < 0.95"),
		"faraway water and opaque foam skip premium lighting work")
	var start: int = src.find("// Sun glitter reuses")
	var stop: int = src.find("#endif", start)
	t.check(start >= 0 and stop > start,
		"the whole sun glint effect is bounded by premium compile-time gating")
	if start >= 0 and stop > start:
		var premium: String = src.substr(start, stop - start)
		t.check(not premium.contains("texture(") and
			not premium.contains("textureLod("),
			"the glint uses no additional screen, normal or sky texture reads")
		t.check(premium.contains("min(0.16") and
			premium.contains("sun_glitter_strength"),
			"sun sparkle cannot exceed its strict HDR energy contribution")
	t.check(src.contains("shore_glimmer") and
		src.contains("refraction_delta") and src.contains("spectral_transmission"),
		"existing foam, refracted scene and spectral water remain intact")

	t.current = "runtime shader binding uses the cached renderer-aware material"
	var material := ShaderMaterial.new()
	var high_profile: Dictionary = VisualProfiles.settings(2)
	WaterRefraction.apply(material, high_profile, 2, "forward_plus")
	t.eq(material.shader, high, "High uses the cached water shader")
	t.near(float(material.get_shader_parameter("sun_glitter_strength")), 0.38,
		0.000001, "real GPU shader material receives High's sunlight budget")
	var ultra_profile: Dictionary = VisualProfiles.settings(3)
	WaterRefraction.apply(material, ultra_profile, 3, "forward_plus")
	t.eq(material.shader, ultra, "Ultra reuses High's shader, no extra compile")
	t.near(float(material.get_shader_parameter("sun_glitter_strength")), 0.8,
		0.000001, "Ultra strengthens real surface sun glints")
	WaterRefraction.apply(material, VisualProfiles.settings(0), 0,
		"forward_plus")
	t.eq(material.shader, low, "Performance switches back to the low GPU variant")
	var source_code: String = (WaterRefraction as Script).source_code
	t.check(source_code.contains('material.set_shader_parameter("sun_glitter_strength"'),
		"all runtime graphics switches apply the new value")
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(atmosphere.contains('global_shader_parameter_set(&"aa_sun_radiance"'),
		"glitter is driven by actual day/night and storm-adjusted sun energy")
