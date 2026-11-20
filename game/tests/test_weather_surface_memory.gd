extends RefCounted
## Rain ripples require current rainfall; soil, grass and foliage stay wet
## after a storm. All material paths consume the existing two GPU globals.
const Moisture = preload("res://scripts/client/weather_surface_memory.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Chunk = preload("res://scripts/client/chunk_view.gd")
const Grass = preload("res://scripts/client/grass_field.gd")
const Foliage = preload("res://scripts/client/foliage.gd")


func run(t) -> void:
	t.current = "saturation and slow drying"
	var wet := 0.0
	for i in 120:
		wet = Moisture.next_wetness(wet, 1.0, 0.8, 0.7,
			Vector2(4.0, 2.0), "plains", 0.1)
	t.check(wet > 0.90 and wet <= 1.0, "sustained rain makes the terrain visibly soaked")
	var just_stopped := wet
	for i in 100:
		wet = Moisture.next_wetness(wet, 0.0, 1.0, 0.8,
			Vector2(0.0, 0.0), "plains", 0.1)
	t.check(wet < just_stopped and wet > 0.65,
		"dry road stays wet for several seconds rather than snapping to zero")
	var swamp: float = just_stopped
	var mountain: float = just_stopped
	for i in 300:
		swamp = Moisture.next_wetness(swamp, 0.0, 1.0, 0.8,
			Vector2.ZERO, "swamp", 0.1)
		mountain = Moisture.next_wetness(mountain, 0.0, 1.0, 0.8,
			Vector2(16.0, 0.0), "mountain", 0.1)
	t.check(swamp > mountain and mountain >= 0.0,
		"shaded wetlands retain moisture longer than windy sunlit rock")
	var night: float = just_stopped
	var noon: float = just_stopped
	for i in 200:
		night = Moisture.next_wetness(night, 0.0, 0.0, -0.6,
			Vector2.ZERO, "forest", 0.1)
		noon = Moisture.next_wetness(noon, 0.0, 1.0, 0.9,
			Vector2.ZERO, "forest", 0.1)
	t.check(night > noon, "sunny midday accelerates evaporation")
	t.current = "bounded invalid input and frame stalls"
	for bad in [NAN, INF, -INF, -1.0, 12.0]:
		var out: float = Moisture.next_wetness(bad, NAN, INF, -INF,
			Vector2(INF, NAN), "invalid", 0.1)
		t.check(is_finite(out) and out >= 0.0 and out <= 1.0,
			"invalid weather and old state never poison shader values")
	t.near(Moisture.next_wetness(0.5, 1.0, 1.0, 1.0,
		Vector2.ZERO, "plains", NAN), 0.5, 0.0001, "NaN delta is ignored")
	t.near(Moisture.next_wetness(0.5, 1.0, 1.0, 1.0,
		Vector2.ZERO, "plains", 0.0), 0.5, 0.0001, "paused frame is stable")
	t.near(Moisture.next_wetness(0.5, 1.0, 1.0, 1.0,
		Vector2.ZERO, "plains", 100.0),
		Moisture.next_wetness(0.5, 1.0, 1.0, 1.0,
		Vector2.ZERO, "plains", Moisture.MAX_STEP), 0.0001,
		"stalled frame cannot instantly saturate an entire region")
	t.near(Moisture.active_rain(INF), 0.0, 0.0001, "invalid active rain disabled")
	t.current = "real GPU material wiring"
	t.check(ProjectSettings.has_setting("shader_globals/aa_weather_rain"),
		"current precipitation is separately registered")
	var setting: Dictionary = ProjectSettings.get_setting("shader_globals/aa_weather_rain", {})
	t.eq(str(setting.get("type", "")), "float", "rain is one GPU scalar")
	t.near(float(setting.get("value", -1.0)), 0.0, 0.0001, "dry startup stays dry")
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(atmosphere_code.contains("Moisture.next_wetness("),
		"shared atmosphere uses persistent material moisture")
	t.check(atmosphere_code.contains('&"aa_weather_wetness", _surface_wetness'),
		"soil moisture reaches the original global material parameter")
	t.check(atmosphere_code.contains('&"aa_weather_rain", Moisture.active_rain(storm)'),
		"active rain reaches a separate shader global")
	var ground := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(ground != null, "textured terrain shader loads")
	if ground != null:
		t.check(ground.code.contains("global uniform float aa_weather_rain;"),
			"PBR terrain receives active rainfall")
		t.check(ground.code.contains("aa_puddle_ripple_strength > 0.001 && aa_weather_rain > 0.005"),
			"drying puddles have no continuing falling raindrop rings")
	t.check(Chunk.GROUND_SHADER.contains("global uniform float aa_weather_rain;"),
		"fallback terrain receives the same two weather signals")
	t.check(Chunk.GROUND_SHADER.contains("aa_puddle_ripple_strength > 0.001 && aa_weather_rain > 0.005"),
		"fallback animated rings stop at rainfall end")
	t.check(Grass.SHADER_CODE.contains("clamp(aa_weather_rain, 0.0, 1.0) * 0.2"),
		"grass gust amplification stops when rainfall ends")
	t.check(Grass.SHADER_CODE.contains("float wet_grass = clamp(aa_weather_wetness"),
		"grass remains dark and glossy while still wet")
	t.check(Foliage.SHADER_CODE.contains("clamp(aa_weather_rain, 0.0, 1.0) * 0.25"),
		"tree gust amplification responds to weather, not retained water")
	t.check(Foliage.SHADER_CODE.contains("float wet_foliage = clamp(aa_weather_wetness"),
		"wet tree leaves retain their PBR highlights")
	var water := load("res://assets/shaders/water.gdshader") as Shader
	if water != null:
		t.check(water.code.contains("float storm = clamp(aa_weather_rain"),
			"open water whitecaps respond to active storms not soaked soil")
