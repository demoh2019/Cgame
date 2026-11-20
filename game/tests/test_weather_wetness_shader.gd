extends RefCounted
## Regression checks for renderer-wide rain wetness. No graphics device is required.

const ChunkView = preload("res://scripts/client/chunk_view.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "global terrain wetness"
	t.check(ProjectSettings.has_setting("shader_globals/aa_weather_wetness"), "rain wetness global is registered")
	var setting: Dictionary = ProjectSettings.get_setting("shader_globals/aa_weather_wetness", {})
	t.eq(str(setting.get("type", "")), "float", "wetness parameter is a scalar")
	t.near(float(setting.get("value", -1.0)), 0.0, 0.0001, "dry weather is the initial material state")
	var textured := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(textured != null, "PBR terrain shader loads")
	if textured != null:
		t.check(textured.code.contains("global uniform float aa_weather_wetness"), "textured terrain uses global rain wetness")
		t.check(textured.code.contains("puddle"), "wet mud and roads get localized puddle highlights")
	t.check(ChunkView.GROUND_SHADER.contains("global uniform float aa_weather_wetness"), "fallback terrain reacts to rain")
	t.check(ChunkView.GROUND_SHADER.contains("puddle"), "untextured fallback preserves weather response")
	# The update path remains on the existing weather controller; the rendering budget is one global uniform.
	var controller_script := Atmosphere as Script
	t.check(controller_script != null, "weather controller is loadable")
	if controller_script != null:
		t.check(controller_script.source_code.contains("global_shader_parameter_set"), "storm drives global wetness")
