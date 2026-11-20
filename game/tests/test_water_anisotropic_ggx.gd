extends RefCounted
## Physics-inspired anisotropic reflections on moving water, renderer-gated.
const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "anisotropic water material quality budget"
	var previous: float = -1.0
	for tier in 4:
		var preset: Dictionary = Profiles.settings(tier)
		var strength: float = float(preset.get("water_anisotropy_strength", -1.0))
		t.check(is_finite(strength) and strength >= 0.0 and strength <= 0.45,
			"wind-stretched reflection budget remains finite and safe")
		t.check(strength >= previous, "quality does not reduce glint detail")
		previous = strength
	t.near(float(Profiles.settings(0)["water_anisotropy_strength"]), 0.0, 0.0001,
		"Performance remains isotropic")
	t.near(float(Profiles.settings(1)["water_anisotropy_strength"]), 0.0, 0.0001,
		"Balanced remains isotropic")
	t.check(float(Profiles.settings(3)["water_anisotropy_strength"]) >
			float(Profiles.settings(2)["water_anisotropy_strength"]),
		"Ultra resolves stronger wind-aligned specular streaks")

	t.current = "premium shader owns the optional BRDF"
	var shader := load("res://assets/shaders/water.gdshader") as Shader
	t.check(shader != null, "water source loads")
	if shader != null:
		var code: String = shader.code
		t.check(code.contains("#ifdef WATER_REFRACTION") and
			code.contains("ANISOTROPY = clamp(wind_anisotropy_strength"),
			"high-end wave reflection changes native GGX anisotropy")
		t.check(code.contains("ANISOTROPY_FLOW = normalize(wind_flow)"),
			"stretch direction follows the shared wind, not the camera")
		t.check(code.contains("TANGENT = vec3(1.0, 0.0, 0.0)") and
			code.contains("BINORMAL = vec3(0.0, 0.0, 1.0)"),
			"native GGX receives a deterministic water tangent basis")
		t.check(code.contains("foam < 0.95") and code.contains("* detail_fade"),
			"foam and distant water do not stretch shiny reflections")
		t.check(not code.contains("anisotropy_flowmap") and
			not code.contains("anisotropy_detail_tex"),
			"water optics add zero GPU textures and geometry passes")
	var low: Shader = WaterRefraction.shader_for(0, "forward_plus")
	var high: Shader = WaterRefraction.shader_for(2, "forward_plus")
	t.check(low != null and high != null and low != high,
		"premium and low-end are separately cached shader variants")
	if high != null:
		t.check(high.code.contains("#define WATER_REFRACTION"),
			"high-end branch compiles anisotropic GGX and scene refraction")
	t.check(not WaterRefraction.enabled(3, "gl_compatibility") and
		not WaterRefraction.enabled(3, "mobile"),
		"unsupported renderers never use the expensive BRDF")
	var material := ShaderMaterial.new()
	WaterRefraction.apply(material, Profiles.settings(3), 3, "forward_plus")
	t.near(float(material.get_shader_parameter("wind_anisotropy_strength")), 0.40, 0.0001,
		"actual material receives ultra water anisotropy")
	WaterRefraction.apply(material, Profiles.settings(2), 2, "forward_plus")
	t.near(float(material.get_shader_parameter("wind_anisotropy_strength")), 0.24, 0.0001,
		"quality switching reuses the existing water material")

	t.current = "live renderer wiring"
	var source: String = (GraphicsQuality as Script).source_code
	t.check(source.contains("WaterRefraction.apply("),
		"live solo and multiplayer graphics paths configure premium water")
