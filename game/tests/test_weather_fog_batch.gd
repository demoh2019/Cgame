extends RefCounted
## Same on a stock Godot binary or the custom fork: batched atmospheric
## color, height and density must have identical visible results.

const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")
const BiomeAtmosphere = preload("res://scripts/client/biome_atmosphere.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "native atomic weather update and stock Godot fallback agree"
	var environment := Environment.new()
	var settings: Dictionary = CinematicFog.profile(2, "forward_plus")
	var biome: Dictionary = BiomeAtmosphere.settings("swamp")
	var clear_color := Color(0.48, 0.54, 0.63)
	var input_density := 0.0034
	var weather: Dictionary = CinematicFog.weather(0.6, 0.1, 0.5, settings)
	CinematicFog.apply_weather(environment, 0.6, 0.1, 0.5, settings,
		clear_color, biome, {"color": clear_color, "density": input_density})
	var expected_color: Color = clear_color.lerp(biome["tint"],
		float(biome["tint_amount"]) * 0.6)
	t.eq(environment.fog_light_color, expected_color,
		"sunlit biome fog is blended from the original sky color exactly once")
	t.near(environment.fog_density, input_density, 0.0000001,
		"distance fog stays synchronized with the server's weather")
	t.near(environment.fog_height, 2.6, 0.0000001,
		"native transaction retains the original sea-level height")
	t.near(environment.fog_height_density,
		minf(float(weather["height_density"]) * float(biome["height_factor"]),
			CinematicFog.MAX_HEIGHT_DENSITY), 0.0000001,
		"native update retains bounded biome-aware mist density")
	t.near(environment.fog_sun_scatter, float(weather["sun_scatter"]),
		0.0000001, "same direct-sun scattering participates in the fog")

	# Reapplying the same input cannot progressively tint every new frame.
	var first_color: Color = environment.fog_light_color
	CinematicFog.apply_weather(environment, 0.6, 0.1, 0.5, settings,
		clear_color, biome, {"color": clear_color, "density": input_density})
	t.eq(environment.fog_light_color, first_color,
		"repeated low-level updates never accumulate green biome tint")
	var desert: Dictionary = BiomeAtmosphere.settings("mountain")
	CinematicFog.apply_weather(environment, 0.75, 0.55, 0.0, settings,
		clear_color, desert, {"color": clear_color, "density": 0.0016})
	t.check(environment.fog_light_color != first_color,
		"crossing biomes updates real world fog without stale previous color")
	t.near(environment.fog_density, 0.0016, 0.0000001,
		"clear mountain air returns to light fog density")

	t.current = "engine batch is discovered at runtime without requiring a fork"
	var cinematic_code: String = (CinematicFog as Script).source_code
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(cinematic_code.contains('env.has_method("configure_weather_fog")'),
		"the game detects native support rather than assuming custom binaries")
	t.check(cinematic_code.contains('env.call("configure_weather_fog"'),
		"supported engines send only one coherent weather transaction")
	t.check(cinematic_code.contains("env.fog_height_density = height_density"),
		"stock Godot still receives the matching fog result")
	t.check(atmosphere_code.contains('"color": base_fog_color') and
		atmosphere_code.contains('"density": base_fog_density'),
		"the actual day/night game passes one sky-derived base color")
	t.check(atmosphere_code.contains("CinematicFog.apply_weather("),
		"the live weather pipeline uses the shared integration")
	if environment.has_method("configure_weather_fog"):
		environment.call("configure_weather_fog", Color(0.2, 0.3, 0.4),
			0.005, 2.1, 0.0011, 0.12)
		t.eq(environment.fog_light_color, Color(0.2, 0.3, 0.4),
			"native fork applies the complete color transaction")
		t.near(environment.fog_height_density, 0.0011, 0.0000001,
			"native fork also updates height fog through the same call")
