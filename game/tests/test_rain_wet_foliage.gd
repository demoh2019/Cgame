extends RefCounted
## Wet vegetation rendering is shared by every streamed foliage mesh and grass
## instance. This regression suite needs no GPU and no downloaded nature pack.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "single registered GPU global for foliage rain gloss"
	t.check(ProjectSettings.has_setting("shader_globals/aa_vegetation_wet_gloss"),
		"foliage material quality knob is registered in the Godot project")
	var setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_vegetation_wet_gloss", {})
	t.eq(str(setting.get("type", "")), "float",
		"foliage wet-gloss knob is a single scalar global")
	t.check(float(setting.get("value", -1.0)) >= 0.0 and
		float(setting.get("value", -1.0)) <= 1.0,
		"default shader value is safely normalized")
	var previous := -1.0
	for level in range(4):
		var preset: Dictionary = VisualProfiles.settings(level)
		var gloss: float = float(preset.get("wet_leaf_gloss", -1.0))
		t.check(gloss >= 0.0 and gloss <= 1.0,
			"graphics tier wet-gloss factor remains bounded")
		t.check(gloss >= previous,
			"gloss detail is monotonic from Performance to Ultra")
		previous = gloss
	t.eq(float(VisualProfiles.settings(0)["wet_leaf_gloss"]), 0.0,
		"Performance does not pay for shiny wet leaves")
	t.eq(float(VisualProfiles.settings(3)["wet_leaf_gloss"]), 1.0,
		"Ultra enables full specular rain response")
	t.eq(VisualProfiles.settings(-1)["wet_leaf_gloss"],
		VisualProfiles.settings(0)["wet_leaf_gloss"],
		"quality below zero clamps")
	t.eq(VisualProfiles.settings(999)["wet_leaf_gloss"],
		VisualProfiles.settings(3)["wet_leaf_gloss"],
		"quality above Ultra clamps")

	t.current = "wet leaves keep original PBR texture and cut-out coverage"
	var leaf_shader: String = Foliage.SHADER_CODE
	t.check(leaf_shader.contains("global uniform float aa_weather_wetness;"),
		"wetness comes from the existing world weather global")
	t.check(leaf_shader.contains("global uniform float aa_vegetation_wet_gloss;"),
		"leaf gloss uses only the quality-controlled GPU global")
	t.check(leaf_shader.contains(
		"float wet_gloss = wet_foliage * clamp(aa_vegetation_wet_gloss"),
		"dry days stay matte regardless of graphics preset")
	t.check(leaf_shader.contains("ROUGHNESS = clamp(mix(roughness * foliage_variation,"),
		"wetness blends with rather than discards original PBR roughness")
	t.check(leaf_shader.contains("SPECULAR = clamp(mix(material_specular, 0.7, wet_gloss)"),
		"rain improves real direct-light leaf reflections")
	t.check(leaf_shader.contains("ALPHA_SCISSOR_THRESHOLD = scissor;"),
		"leaf cut-out shadows and silhouettes remain unchanged")
	t.check(leaf_shader.contains("use_normal_map") and leaf_shader.contains("use_orm_map"),
		"imported normal and ORM maps are preserved")
	t.check(leaf_shader.contains("normal_fade > 0.01"),
		"far foliage avoids sampling tiny normal details")

	t.current = "rain-wet grass shares wind and light without more geometry"
	var grass_shader: String = GrassField.SHADER_CODE
	t.check(grass_shader.contains("global uniform float aa_weather_wetness;"),
		"grass uses the same synchronized weather as terrain")
	t.check(grass_shader.contains("float storm_wind = 1.0 + clamp(aa_weather_wetness"),
		"storm wind moves existing MultiMesh grass more naturally")
	t.check(grass_shader.contains("wet_grass = clamp(aa_weather_wetness"),
		"grass blades darken with rain")
	t.check(grass_shader.contains("shadows_disabled;"),
		"billions of tiny grass shadow fragments are still avoided")
	t.check(grass_shader.contains("if (shrink > 0.001)"),
		"distant blades continue skipping wind trigonometry")

	t.current = "preset and weather update paths are shared with the game"
	var renderer_code: String = (GraphicsQuality as Script).source_code
	t.check(renderer_code.contains(
		"global_shader_parameter_set(&\"aa_vegetation_wet_gloss\""),
		"quality changes update one global rather than each tree material")
	t.check(renderer_code.contains("float(world_profile[\"wet_leaf_gloss\"])"),
		"quality selector reads the saved visual preset")
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(atmosphere_code.contains(
		"global_shader_parameter_set(&\"aa_weather_wetness\", storm)"),
		"storm smoothly supplies the world material wetness")
