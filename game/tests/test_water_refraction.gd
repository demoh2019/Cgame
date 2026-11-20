extends RefCounted
## Refraction fidelity and renderer performance gates; no GPU readback.
const WaterRefraction = preload("res://scripts/client/graphics_water_refraction.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "water refraction: no low-end framebuffer copy"
	for tier in 2:
		var p: Dictionary = WaterRefraction.settings(tier, "forward_plus")
		t.check(not bool(p["enabled"]), "Performance/Balanced skip screen-refraction pass")
		t.near(float(p["strength"]), 0.0, 0.00001, "low presets disable optical offset")
	for method in ["mobile", "gl_compatibility", ""]:
		for tier in 4:
			t.check(not bool(WaterRefraction.settings(tier, method)["enabled"]),
					"unsupported renderer never uses screen-copy water")

	t.current = "shore refraction quality and distance budgets"
	var high: Dictionary = WaterRefraction.settings(2, "forward_plus")
	var ultra: Dictionary = WaterRefraction.settings(3, "forward_plus")
	t.check(bool(high["enabled"]) and bool(ultra["enabled"]),
			"Forward+ High and Ultra enable true scene-color refraction")
	t.check(float(high["strength"]) > 0.0 and float(high["strength"]) < float(ultra["strength"]),
			"Ultra has stronger optical displacement")
	t.check(float(high["fade_end"]) > float(high["fade_start"])
			and float(ultra["fade_end"]) > float(high["fade_end"]),
			"only Ultra extends detailed refraction farther from the camera")
	t.check(float(high["max_depth"]) < float(ultra["max_depth"]),
			"Ultra reveals more underwater depth")
	t.eq(WaterRefraction.settings(-10, "forward_plus"), WaterRefraction.settings(0, "forward_plus"),
			"invalid low preset clamps")
	t.eq(WaterRefraction.settings(99, "forward_plus"), ultra,
			"invalid high preset clamps")

	t.current = "Godot material switches without copying low-end scene color"
	var material := ShaderMaterial.new()
	WaterRefraction.apply(material, 1, "forward_plus")
	t.check(material.shader == WaterRefraction.BASE_WATER,
			"Balanced uses original water shader and does not request screen texture")
	WaterRefraction.apply(material, 3, "forward_plus")
	t.check(material.shader == WaterRefraction.REFRACTIVE_WATER,
			"Ultra switches only water material to advanced refraction")
	t.near(float(material.get_shader_parameter("refraction_strength")),
			float(ultra["strength"]), 0.00001, "native Godot shader receives strength")
	WaterRefraction.apply(material, 2, "forward_plus")
	t.near(float(material.get_shader_parameter("refraction_fade_end")),
			float(high["fade_end"]), 0.0001, "live quality switch shortens effect range")
	WaterRefraction.apply(material, 3, "gl_compatibility")
	t.check(material.shader == WaterRefraction.BASE_WATER,
			"renderer fallback disables costly screen-read variant")
	WaterRefraction.apply(null, 3, "forward_plus")
	t.check(true, "missing water material is safe")

	t.current = "GPU water shader retains optical and shoreline effects"
	var base_code: String = WaterRefraction.BASE_WATER.code
	var advanced: String = WaterRefraction.REFRACTIVE_WATER.code
	t.check(not base_code.contains("hint_screen_texture"),
			"low-end shader requires no additional screen color copy")
	t.check(advanced.contains("hint_screen_texture")
			and advanced.contains("hint_depth_texture"), "high-end shader samples scene and depth")
	t.check(advanced.contains("refraction_near") and advanced.contains("refraction_shallow")
			and advanced.contains("refraction_mask"), "distortion is faded by depth and distance")
	t.check(advanced.contains("shifted_depth") and advanced.contains("valid_depth"),
			"foreground cliffs do not leak through distorted water")
	t.check(advanced.contains("refracted - straight")
			and advanced.contains("1.0 - ALPHA"), "distortion affects transmitted light only")
	t.check(advanced.contains("storm_whitecaps") and advanced.contains("shore_glimmer")
			and advanced.contains("spectral_transmission") and advanced.contains("fresnel"),
			"existing water foam, shallow absorption, highlights and Fresnel remain")
	var graphics_code: String = (GraphicsQuality as Script).source_code
	t.check(graphics_code.contains("WaterRefraction.apply(water_shader, _level, str(method))"),
			"live online water material receives the visual preset")
