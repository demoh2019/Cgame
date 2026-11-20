extends RefCounted
## GPU-less shader invariants and preset integration for quality-tiered water.
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "shallow water quality and renderer safeguards"
	var previous: float = -1.0
	for tier in range(4):
		var profile: Dictionary = VisualProfiles.settings(tier)
		var amount: float = float(profile.get("water_refraction_strength", -1.0))
		t.check(amount >= 0.0 and amount <= 1.0,
			"refraction strength is within a bounded physical interpolation")
		t.check(amount >= previous, "higher presets increase detail")
		previous = amount
		t.check(float(profile["water_refraction_start"]) <
			float(profile["water_refraction_end"]),
			"distance-controlled transition cannot invert")
	t.eq(VisualProfiles.settings(0)["water_refraction_strength"], 0.0,
		"Performance never samples the scene")
	t.eq(VisualProfiles.settings(1)["water_refraction_strength"], 0.0,
		"Balanced keeps native cheap water")
	t.check(float(VisualProfiles.settings(2)["water_refraction_strength"]) > 0.5,
		"High shows refracted underwater terrain")
	t.check(float(VisualProfiles.settings(3)["water_refraction_strength"]) > 0.8,
		"Ultra uses stronger shallow-water distortion")
	for renderer in ["mobile", "gl_compatibility", "unknown"]:
		t.check(not WaterRefraction.enabled(3, renderer),
			"other rendering methods avoid the costly scene copy")
	for tier in [0, 1]:
		t.check(not WaterRefraction.enabled(tier, "forward_plus"),
			"low-detail Forward+ skips the extra screen pass")
	t.check(WaterRefraction.enabled(3, "forward_plus"), "Ultra enables refraction")

	t.current = "compile-time shader split and cached variant"
	var base: Shader = WaterRefraction.shader_for(0, "forward_plus")
	var high: Shader = WaterRefraction.shader_for(3, "forward_plus")
	t.check(base != null and high != null, "both shader resources exist")
	if base == null or high == null:
		return
	t.check(base != high, "quality selects a separate shader program")
	t.check(base == WaterRefraction.shader_for(3, "gl_compatibility"),
		"unsupported renderer always uses baseline material")
	t.check(high == WaterRefraction.shader_for(2, "forward_plus"),
		"High and Ultra share one cached variant")
	t.check(not base.code.contains("#define WATER_REFRACTION"),
		"low-cost variant does not define screen refraction")
	t.check(high.code.contains("#define WATER_REFRACTION"),
		"high-end variant compiles screen refraction")
	t.check(base.code.contains("#ifdef WATER_REFRACTION") and
		base.code.contains("hint_screen_texture"),
		"screen texture only exists within conditional preprocessor source")

	t.current = "water shader validates scene depth, viewport and light"
	var code: String = base.code
	t.check(code.contains(
		"refraction_strength > 0.001 && thickness > 0.08 && thickness < 3.8"),
		"offshore/deep water avoids two expensive buffer reads")
	t.check(code.contains("warped_thickness") and
		code.contains("abs(warped_thickness - thickness)") and
		code.contains("depth_guard"),
		"discontinuous depth rejects silhouettes and foreground halos")
	t.check(code.contains("edge_guard") and
		code.contains("clamp(SCREEN_UV + shift"),
		"screen edge distortion is safely bounded")
	t.check(code.contains("textureLod(scene_color_tex"),
		"screen color is actually refracted")
	t.check(code.contains("refraction_delta = refracted_scene - straight_scene")
		and code.contains("transmission_weight"),
		"refracted and straight scene samples form only a transmission difference")
	t.check(code.contains("EMISSION += refraction_delta * transmission_weight"),
		"the already-lit background delta is composed without double lighting")
	t.check(not code.contains("EMISSION += refracted_rgb * refraction_mix")
		and not code.contains("ALBEDO *= 1.0 - 0.66 * refraction_mix"),
		"absolute scene emission and fake surface dimming are removed")
	t.check(not code.contains("ALPHA = clamp(ALPHA + refraction_mix"),
		"refraction preserves water opacity and Fresnel")
	t.check(code.contains("spectral_transmission") and
		code.contains("storm_whitecaps") and code.contains("shore_glimmer"),
		"old physical absorption, storm wave foam and caustics preserved")
	var material := ShaderMaterial.new()
	WaterRefraction.apply(material, VisualProfiles.settings(3), 3, "forward_plus")
	t.check(material.shader == high, "ultra assigns high-quality shader")
	WaterRefraction.apply(material, VisualProfiles.settings(0), 0, "forward_plus")
	t.check(material.shader == base, "low preset releases screen sampler")
	WaterRefraction.apply(material, VisualProfiles.settings(3), 3, "mobile")
	t.check(material.shader == base, "mobile cannot request scene color")
	WaterRefraction.apply(null, VisualProfiles.settings(3), 3, "forward_plus")
	t.check((GraphicsQuality as Script).source_code.contains(
		"WaterRefraction.apply(water_shader, world_profile, _level, str(method))"),
		"live game graphics quality settings actually wire the new material")
