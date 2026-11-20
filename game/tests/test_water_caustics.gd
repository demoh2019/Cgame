extends RefCounted
## Underwater sunlight: one world-aligned shader for both terrain variants.
const Caustics = preload("res://scripts/client/water_caustics.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Online = preload("res://scripts/client/online_main.gd")


func run(t) -> void:
	t.current = "sun and storm control real water caustics"
	t.eq(Caustics.light_factor(0.0, -1.0, 0.0), 0.0, "night skips sunlight")
	t.eq(Caustics.light_factor(1.0, -0.2, 0.0), 0.0, "sun below horizon skips")
	t.near(Caustics.light_factor(1.0, 1.0, 0.0), 1.0, 0.00001,
		"midday allows sunlight caustics")
	t.check(Caustics.light_factor(1.0, 1.0, 1.0) < 0.1,
		"overcast attenuates underwater light")
	t.check(Caustics.light_factor(0.45, 0.2, 0.0) <
		Caustics.light_factor(1.0, 1.0, 0.0), "low sun is dimmer")
	t.eq(Caustics.light_factor(NAN, 1.0, 0.0), 0.0, "NaN daylight ignored")
	t.eq(Caustics.light_factor(1.0, INF, 0.0), 0.0, "infinite sun ignored")
	t.eq(Caustics.light_factor(1.0, 1.0, NAN), 0.0, "NaN storm ignored")
	t.current = "GPU quality and renderer budget"
	t.eq(Caustics.quality_strength(0, "forward_plus"), 0.0,
		"Performance skips caustic math")
	t.eq(Caustics.quality_strength(1, "forward_plus"), 0.0,
		"Balanced skips caustic math")
	t.near(Caustics.quality_strength(2, "forward_plus"), 0.55, 0.00001,
		"High gets one caustic wave layer")
	t.eq(Caustics.quality_strength(3, "forward_plus"), 1.0,
		"Ultra gets the extra refracted sunlight detail")
	t.eq(Caustics.quality_strength(3, "mobile"), 0.0, "Mobile fallback is cheap")
	t.eq(Caustics.quality_strength(3, "gl_compatibility"), 0.0,
		"Compatibility fallback is cheap")
	t.eq(Caustics.quality_strength(-1, "forward_plus"), 0.0, "negative tier clamps")
	t.eq(Caustics.quality_strength(9, "forward_plus"), 1.0, "Ultra tier clamps")
	t.eq(Caustics.UPDATES_PER_SECOND, 5.0, "one sunlight uniform updates at 5 Hz")
	t.current = "shader globals and game sea height"
	for name in ["aa_water_caustics_strength", "aa_water_caustics_sun"]:
		t.check(ProjectSettings.has_setting("shader_globals/" + name),
			"shader global is registered before materials compile")
		var config: Dictionary = ProjectSettings.get_setting("shader_globals/" + name, {})
		t.eq(str(config.get("type", "")), "float", "shader global has float type")
		t.eq(float(config.get("value", -1.0)), 0.0, "safe default is dark")
	t.near(Defs.WATER_LEVEL - 0.35, -0.35, 0.00001,
		"shallow caustics match water plane world height")
	t.check((Online as Script).source_code.contains(
		"water.position.y = Defs.WATER_LEVEL - 0.35"), "water renderer agrees")
	t.current = "shared procedural sunlight shader and underwater LOD"
	var source: String = FileAccess.get_file_as_string(
		"res://assets/shaders/water_caustics.gdshaderinc")
	t.check(source.contains("aa_water_caustic_lace(vec2 world_xz"),
		"caustics projected across chunk boundaries")
	t.check(source.contains("aa_water_caustic_illumination(vec2 world_xz"),
		"both terrain materials can share one function")
	t.check(source.contains("aa_water_caustics_strength <= 0.001"),
		"quality zero avoids GPU wave trigonometry")
	t.check(source.contains("aa_water_caustics_sun <= 0.001"),
		"night skip before wave computation")
	t.check(source.contains("world_height >= -0.35") and
		source.contains("world_height < -4.85"), "only submerged ground is affected")
	t.check(source.contains("camera_distance > 48.0"),
		"distant water avoids pixel wave calculations")
	t.check(source.contains("upward_normal < 0.45"),
		"vertical cliffs remain physically believable")
	t.check(source.contains("if (aa_water_caustics_strength > 0.75)"),
		"only Ultra pays for a second caustic layer")
	t.check(not source.contains("texture(") and not source.contains("SCREEN_UV"),
		"no extra screen pass or texture tap")
	t.current = "real graphics quality, PBR and fallback integration"
	var pbr := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(pbr != null, "textured PBR terrain loads")
	if pbr != null:
		t.check(pbr.code.contains("water_caustics.gdshaderinc"),
			"thirteen PBR terrain layers receive underwater sun caustics")
		t.check(pbr.code.contains("aa_water_caustic_illumination("),
			"physically illuminated terrain includes underwater pattern")
		t.check(pbr.code.contains("filter_specular_roughness(final_roughness, bent)"),
			"existing microfacet filtering and PBR are preserved")
	t.check(ChunkView.GROUND_SHADER.contains("water_caustics.gdshaderinc"),
		"Compatibility painted terrain uses the same wave pattern")
	t.check(ChunkView.GROUND_SHADER.contains("aa_water_caustic_illumination("),
		"procedural fallback shades submerged rocks and sand")
	t.check((GraphicsQuality as Script).source_code.contains(
		"WaterCaustics.quality_strength(_level, str(method))"),
		"quality changes update a single global, not thousands of chunks")
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(atmosphere.contains("WaterCaustics.light_factor(daylight, sun_height, storm)"),
		"real time of day and weather drive underwater sunlight")
	t.check(atmosphere.contains(
		"_caustic_publish_seconds >= 1.0 / WaterCaustics.UPDATES_PER_SECOND"),
		"sunlight GPU global upload is rate limited")
