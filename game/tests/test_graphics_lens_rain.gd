extends RefCounted
## Screen-space rain is bounded, optional and fused with the existing grade.
const Lens = preload("res://scripts/client/graphics_lens_rain.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "storm-lens budget and zero-work fallbacks"
	t.near(Lens.strength_for(1.0, 0, "forward_plus"), 0.0, 0.00001,
		"Performance never renders rain on lens")
	t.near(Lens.strength_for(1.0, 1, "forward_plus"), 0.0, 0.00001,
		"Balanced never renders a screen-space raindrop")
	t.near(Lens.strength_for(1.0, 3, "mobile"), 0.0, 0.00001,
		"mobile avoids extra pixel shader branches")
	t.near(Lens.strength_for(1.0, 3, "gl_compatibility"), 0.0, 0.00001,
		"GL compatibility remains at original graphics cost")
	t.near(Lens.strength_for(1.0, 3, "forward_plus", true, false),
		0.0, 0.00001, "dungeons have no artificial rainy lens")
	t.near(Lens.strength_for(1.0, 3, "forward_plus", false, true),
		0.0, 0.00001, "indoors immediately eliminates water droplets")
	t.near(Lens.strength_for(0.0, 3, "forward_plus"), 0.0, 0.00001,
		"clear weather takes shader fast path")
	t.near(Lens.strength_for(Lens.START_STORM, 3, "forward_plus"),
		0.0, 0.00001, "gentle drizzles do not obstruct camera")
	t.near(Lens.strength_for(1.0, 2, "forward_plus"), 0.32, 0.00001,
		"High uses restrained rain distortion")
	t.near(Lens.strength_for(1.0, 3, "forward_plus"),
		Lens.MAX_STRENGTH, 0.00001, "Ultra reserves highest lens budget")
	t.near(Lens.strength_for(0.69, 3, "forward_plus"), 0.30, 0.00001,
		"rain strength fades continuously with the storm")
	for invalid in [NAN, INF, -INF]:
		t.eq(Lens.strength_for(invalid, 3, "forward_plus"), 0.0,
			"invalid weather cannot trigger a shader NaN")
	t.eq(Lens.strength_for(1.0, 900, "forward_plus"),
		Lens.MAX_STRENGTH, "quality clamps to highest tier")
	t.near(Lens.screen_wind(Vector2.INF).length(), 0.0, 0.00001,
		"invalid wind never distorts screen")
	t.near(Lens.screen_wind(Vector2(2.0, 0.0)).length(),
		2.0 / 6.0, 0.00001, "real wind smoothly steers the droplet field")
	t.check(Lens.screen_wind(Vector2(1000.0, 0.0)).length() <= 1.0,
		"severe weather still bounds lens movement")

	t.current = "same postprocess texture, no additional fullscreen stage"
	var material := ShaderMaterial.new()
	var shader := load("res://assets/shaders/post_grade.gdshader") as Shader
	t.check(shader != null, "the game's existing screen pass loads")
	if shader == null:
		return
	material.shader = shader
	var src: String = shader.code
	t.check(src.contains("uniform float lens_rain_strength = 0.0;"),
		"no-op is default even before graphics settings initialize")
	t.check(src.contains("if (lens_rain_strength > 0.001)"),
		"clear or low-quality weather skips all raindrop calculations")
	t.check(src.contains("if (coverage > 0.001)"),
		"extra screen texture sample occurs only within a visible droplet")
	t.check(src.contains("vec3 behind_drop = texture(screen, refracted_uv).rgb"),
		"real behind-scene color drives physically oriented lens bending")
	t.check(src.contains("SCREEN_PIXEL_SIZE") and src.contains("safe_center"),
		"refraction is pixel-bounded and preserves the player's focus")
	t.check(src.contains("blur_quality > 0") and src.contains("sharpen_strength >"),
		"previous tilt-shift and contrast adaptive sharpening are intact")
	t.check(src.find("if (lens_rain_strength > 0.001)") >
		src.find("if (sharpen_strength > 0.001") and
		src.find("if (lens_rain_strength > 0.001)") <
		src.find("// Split toning:"),
		"rain droplets composite after peripheral blur, before cinematic color")
	t.check(src.contains("deband_strength > 0.001"),
		"existing filmic sky debanding remains")
	Lens.apply(material, 1.0, 3, "forward_plus", Vector2(3.0, 4.0))
	t.near(float(material.get_shader_parameter("lens_rain_strength")),
		Lens.MAX_STRENGTH, 0.00001, "real post material uses Ultra level")
	t.check((material.get_shader_parameter("lens_rain_wind") as Vector2).length() > 0.0,
		"smoothed game weather sets shader wind")
	Lens.apply(material, 1.0, 3, "forward_plus", Vector2(3.0, 4.0),
		false, true)
	t.near(float(material.get_shader_parameter("lens_rain_strength")),
		0.0, 0.00001, "shelter disables visible raindrops immediately")
	t.eq(material.get_shader_parameter("lens_rain_wind"), Vector2.ZERO,
		"rain shader stops moving when outdoors becomes sheltered")

	t.current = "online gameplay integration"
	var code: String = (Online as Script).source_code
	t.check(code.contains("GraphicsLensRain.apply(_grade_material"),
		"real online scene calls the existing post material")
	t.check(code.contains("GraphicsColorGrade.apply(_grade_material") and
		code.contains("_grade_elapsed >= 0.20"),
		"lens update shares bounded 5 Hz grade cadence")
	t.check(code.contains('bool(weather.get("sheltered", false))'),
		"authoritative weather shelters prevent wet-camera artifacts")
	t.check(Quality.profile(0)["glow"] == false,
		"low-end preset's existing bloom budget is unchanged")
