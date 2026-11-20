extends RefCounted
## The same low-cost fog resources are reused by all biomes and renderers.
const BiomeAtmosphere = preload("res://scripts/client/biome_atmosphere.gd")
const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const OnlineGame = preload("res://scripts/client/online_main.gd")
const OfflineGame = preload("res://scripts/client/client_main.gd")

func run(t) -> void:
	t.current = "biome fog presets are bounded and independent"
	var plains: Dictionary = BiomeAtmosphere.settings("plains")
	var swamp: Dictionary = BiomeAtmosphere.settings("swamp")
	var forest: Dictionary = BiomeAtmosphere.settings("forest")
	var mountains: Dictionary = BiomeAtmosphere.settings("mountain")
	var beach: Dictionary = BiomeAtmosphere.settings("beach")
	t.eq(BiomeAtmosphere.settings("unknown"), plains,
		"missing/unknown biomes keep original world atmosphere")
	t.check(float(swamp["height_factor"]) > float(plains["height_factor"]),
		"swamps hold more humid near-ground mist")
	t.check(float(mountains["height_factor"]) < float(plains["height_factor"]),
		"mountains have thinner cleaner air")
	t.check(float(forest["height_factor"]) > float(plains["height_factor"]),
		"forests have gentle sheltered humidity")
	t.check(float(beach["height_factor"]) < float(plains["height_factor"]),
		"open coastline has lighter near-ground fog")
	for kind in ["swamp", "forest", "mountain", "beach", "plains", "unknown"]:
		var profile: Dictionary = BiomeAtmosphere.settings(kind)
		t.check(float(profile["height_factor"]) >= BiomeAtmosphere.MIN_HEIGHT_FACTOR
			and float(profile["height_factor"]) <= BiomeAtmosphere.MAX_HEIGHT_FACTOR,
			"all height fog factors are within the GPU budget")
		t.check(float(profile["volume_factor"]) >= BiomeAtmosphere.MIN_VOLUME_FACTOR
			and float(profile["volume_factor"]) <= BiomeAtmosphere.MAX_VOLUME_FACTOR,
			"all volume fog factors stay bounded")
		t.check(float(profile["tint_amount"]) >= 0.0
			and float(profile["tint_amount"]) <= BiomeAtmosphere.MAX_TINT_AMOUNT,
			"tint never overrides the source sky")
	var damaged: Dictionary = BiomeAtmosphere.settings("swamp")
	damaged["height_factor"] = 100.0
	t.check(float(BiomeAtmosphere.settings("swamp")["height_factor"]) < 2.0,
		"callers cannot mutate global presets")

	t.current = "safe transitions across world biome boundaries"
	t.eq(BiomeAtmosphere.advance(plains, "swamp", 0.0), plains,
		"zero frame delta keeps the old look")
	t.eq(BiomeAtmosphere.advance(plains, "swamp", NAN), plains,
		"bad frame delta does not affect fog")
	var halfway: Dictionary = BiomeAtmosphere.advance(plains, "swamp", 0.1)
	t.check(float(halfway["height_factor"]) > 1.0
		and float(halfway["height_factor"]) < float(swamp["height_factor"]),
		"mist eases in instead of popping")
	t.check(float(BiomeAtmosphere.advance(halfway, "swamp", 0.1)["height_factor"])
		> float(halfway["height_factor"]), "continued frames converge")
	t.near(float(BiomeAtmosphere.advance(plains, "swamp", 100.0)["height_factor"]),
		float(BiomeAtmosphere.advance(plains, "swamp", 0.25)["height_factor"]),
		0.00001, "loading stalls do not flash the full density change")

	t.current = "one Environment changes hue and density without new fog passes"
	var env := Environment.new()
	env.fog_light_color = Color(0.64, 0.73, 0.83)
	var balanced: Dictionary = CinematicFog.profile(1, "gl_compatibility")
	var high: Dictionary = CinematicFog.profile(2, "forward_plus")
	var sky: Color = Color(0.64, 0.73, 0.83)
	CinematicFog.apply_weather(env, 0.85, 0.7, 0.2, balanced, sky, plains)
	var base_density: float = env.fog_height_density
	var base_color: Color = env.fog_light_color
	CinematicFog.apply_weather(env, 0.85, 0.7, 0.2, balanced, sky, swamp)
	t.check(env.fog_height_density > base_density,
		"swamp increases actual built-in fog density")
	t.check(env.fog_height_density <= CinematicFog.MAX_HEIGHT_DENSITY,
		"swamp cannot exceed safe height fog density")
	t.check(env.fog_light_color != base_color,
		"swamp changes existing fog color without an overlay")
	t.check(not env.volumetric_fog_enabled,
		"Compatibility never creates a second volumetric pass")
	CinematicFog.apply_weather(env, 0.85, 0.7, 0.2, balanced, sky, mountains)
	t.check(env.fog_height_density < base_density,
		"mountains make existing fog less dense")
	CinematicFog.apply_weather(env, 0.85, 0.7, 0.2, high, sky, swamp)
	t.check(env.volumetric_fog_density <= CinematicFog.MAX_VOLUME_DENSITY,
		"Forward+ regional fog respects volume density cap")
	env.fog_light_color = sky
	CinematicFog.apply_weather(env, 0.0, -0.4, 0.0, balanced, sky, swamp)
	t.eq(env.fog_light_color, sky,
		"swamp greens do not recolor moonlit nights")

	t.current = "offline and multiplayer share regional presentation"
	t.check((Atmosphere as Script).source_code.contains("BiomeAtmosphere.advance("),
		"all fog transitions are driven by shared atmosphere")
	t.check((OnlineGame as Script).source_code.contains("_visual_biome ="),
		"online world samples its own biome at the weather cadence")
	t.check((OfflineGame as Script).source_code.contains("_visual_biome ="),
		"offline preview samples the same authoritative world biome")
