extends RefCounted
## Wind-driven water wave normals and foam share regional weather with foliage.
const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")


func run(t) -> void:
	t.current = "tiered water wave work is bounded and monotonic"
	var last_strength: float = -1.0
	for tier in 4:
		var profile: Dictionary = Profiles.settings(tier)
		var strength: float = float(profile.get("wind_wave_strength", -1.0))
		t.check(is_finite(strength) and strength >= 0.0 and strength <= 1.0,
			"water wind wave budget is finite and capped")
		t.check(strength >= last_strength,
			"higher quality preserves or improves water waves")
		last_strength = strength
	t.eq(Profiles.settings(0)["wind_wave_strength"], 0.0,
		"Performance skips the additional wave trigonometry")
	t.eq(Profiles.settings(1)["wind_wave_strength"], 0.0,
		"Balanced preserves the original cheap water")
	t.check(float(Profiles.settings(2)["wind_wave_strength"]) > 0.0,
		"High adds wind-driven optical waves")
	t.check(float(Profiles.settings(3)["wind_wave_strength"]) >
		float(Profiles.settings(2)["wind_wave_strength"]),
		"Ultra increases wave detail without unbounded frequency")
	t.eq(Profiles.settings(-50)["wind_wave_strength"], 0.0,
		"invalid low quality clamps")
	t.eq(Profiles.settings(99)["wind_wave_strength"],
		Profiles.settings(3)["wind_wave_strength"],
		"invalid high quality clamps")

	t.current = "shared atmospheric wind drives real water material"
	var shader := load("res://assets/shaders/water.gdshader") as Shader
	t.check(shader != null, "real water shader loads")
	if shader == null:
		return
	var code: String = shader.code
	t.check(code.contains("global uniform vec3 aa_vegetation_wind"),
		"water reads the one smoothed regional wind uniform shared with foliage")
	t.check(code.contains("uniform float wind_wave_strength"),
		"water exposes a runtime quality wave budget")
	t.check(code.contains("wind_wave_strength > 0.001 && detail_fade > 0.001"),
		"zero-cost branch in low quality and far from camera")
	t.check(code.contains("aa_vegetation_wind.z > 0.001"),
		"calm water avoids unnecessary wave calculations")
	t.check(code.contains("vec2 wind_dir = normalize(aa_vegetation_wind.xy)"),
		"wave direction follows the weather vector")
	t.check(code.contains("float flow_phase = dot(p, wind_dir)"),
		"waves are anchored to world coordinates without screen swimming")
	t.check(code.contains("cos(flow_phase)") and code.contains("storm * 0.025"),
		"one analytic wave grows with storm strength")
	t.check(code.contains("slope += wind_slope * wind_wave_strength"),
		"existing PBR wave slope receives the optional wind term")
	t.check(code.find("slope += wind_slope") < code.find("refract_slope = slope"),
		"refraction and lighting use the identical final wave field")
	t.check(code.find("slope += wind_slope") < code.find("crest = smoothstep("),
		"whitecap highlights use the same final wave geometry")
	t.check(code.contains("float storm_whitecaps = crest * storm"),
		"existing storm-whitecap lighting remains intact")
	t.check(code.contains("spectral_transmission") and
		code.contains("vec3 refraction_delta"),
		"water absorption and guarded scene refraction are preserved")
	t.check(not code.contains("wind_wave_tex") and
		not code.contains("wind_foam_tex"),
		"new effect needs no textures or VRAM")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wind_wave_strength",
		float(Profiles.settings(3)["wind_wave_strength"]))
	t.near(float(material.get_shader_parameter("wind_wave_strength")),
		0.45, 0.0001,
		"live shader material exposes the actual Ultra wind response")
	var high_variant: Shader = WaterRefraction.shader_for(3, "forward_plus")
	t.check(high_variant != null and high_variant.code.contains("wind_wave_strength"),
		"cached high-end refractive water variant inherits directional waves")

	t.current = "online world and local weather use existing global uniform"
	var source: String = (Quality as Script).source_code
	t.check(source.contains('set_shader_parameter("wind_wave_strength"'),
		"quality switching uploads water wave profile to live material")
	t.check(source.contains('world_profile["wind_wave_strength"]'),
		"runtime water wave budget comes from shared four-quality presets")
	var atmospheric_source: String = (Atmosphere as Script).source_code
	t.check(atmospheric_source.contains('global_shader_parameter_set(&"aa_vegetation_wind"'),
		"smoothed authoritative weather already reaches every GPU water wave")
	t.check(atmospheric_source.contains("_wind_publish_seconds >= 0.1"),
		"wind updates remain rate-limited to 10 Hz")
	var registered: Dictionary = ProjectSettings.get_setting("shader_globals/aa_vegetation_wind", {})
	t.eq(str(registered.get("type", "")), "vec3",
		"project registers the same shared GPU weather data")
