extends RefCounted
## Wind remains client-side, with low-cost per-tree variation and smooth storm response.

const Foliage = preload("res://scripts/client/foliage.gd")


func run(t) -> void:
	t.current = "GPU foliage weather and wind"
	var shader: String = Foliage.SHADER_CODE
	t.check(ProjectSettings.has_setting("shader_globals/aa_weather_wetness"), "weather global exists")
	t.check(shader.contains("global uniform float aa_weather_wetness"), "foliage responds to the common storm factor")
	t.check(shader.contains("float storm_wind = 1.0 + clamp(aa_weather_wetness"), "gust amplitude grows smoothly during storms")
	t.check(shader.contains("if (wind_lod > 0.001 && sway > 0.0)"), "wind trigonometry is skipped for distant trees")
	t.check(shader.contains("smoothstep(wind_fade_start, wind_fade_end"), "foliage animation fades at distance")
	t.check(shader.contains("vec2 hash_uv = fract(root"), "per-tree hue uses arithmetic hash")
	t.check(not shader.contains("sin(dot(root, vec2(12.9898"), "hue no longer evaluates per-vertex sine")
