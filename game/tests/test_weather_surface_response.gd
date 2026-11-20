extends RefCounted
## Graphics-only rain response checks; does not require an active GPU.

const Foliage = preload("res://scripts/client/foliage.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")


func run(t) -> void:
	t.current = "shared weather-driven rendering"
	var water := load("res://assets/shaders/water.gdshader") as Shader
	t.check(water != null, "water shader loads")
	if water != null:
		var code: String = water.code
		t.check(code.contains("global uniform float aa_weather_wetness"), "water uses the existing weather global")
		t.check(code.contains("storm_wave_strength"), "storm strengthens analytic waves")
		t.check(code.contains("storm_whitecaps"), "whitecaps appear during storms")
		t.check(code.contains("hint_depth_texture"), "shoreline foam still uses water depth")
		t.check(code.contains("if (ripple_strength > 0.001)"), "Performance skips wave trigonometry")
		t.check(code.contains("if (ripple_strength > 0.30)"), "microdetail remains quality-gated")
	var foliage: String = Foliage.SHADER_CODE
	t.check(foliage.contains("wet_foliage"), "foliage darkens and changes PBR roughness")
	t.check(foliage.contains("ALPHA_SCISSOR_THRESHOLD"), "leaf transparency remains cut out")
	t.check(foliage.contains("instance_tint"), "foliage instance colors are preserved")
	var grass: String = GrassField.SHADER_CODE
	t.check(grass.contains("global uniform float aa_weather_wetness"), "grass uses shared storm global")
	t.check(grass.contains("wet_grass"), "wet grass color is visibly darker")
	t.check(grass.contains("storm_wind"), "storms increase grass gust amplitude")
	t.check(grass.contains("shrink > 0.001"), "distant grass skips wind animation")
	t.current = "performance budget"
	t.eq(float(VisualProfiles.settings(0)["water_ripples"]), 0.0, "Performance still has no animated water")
	t.check(float(VisualProfiles.settings(3)["water_ripples"]) > 0.30, "Ultra retains high detail water")
	t.check(ProjectSettings.has_setting("shader_globals/aa_weather_wetness"), "shared wetness global is registered")
