extends RefCounted
## Shared online/solo sun lighting adjusts existing soft-shadow properties.
const Shadow = preload("res://scripts/client/sun_shadow_atmosphere.gd")
const Lighting = preload("res://scripts/client/graphics_lighting.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "clear midday, moonlight and clouds affect native shadows"
	var noon: Dictionary = Shadow.profile(3, 1.0, 0.8, 0.0)
	var dusk: Dictionary = Shadow.profile(3, 0.6, 0.12, 0.0)
	var rain: Dictionary = Shadow.profile(3, 1.0, 0.8, 1.0)
	var rainy_dusk: Dictionary = Shadow.profile(3, 0.6, 0.12, 1.0)
	t.near(float(noon["opacity"]), 1.0, 0.0001, "clear noon keeps strong shadows")
	t.check(float(dusk["blur"]) > float(noon["blur"]), "low-angle sun softens shadows")
	t.check(float(rain["blur"]) > float(noon["blur"]), "overcast sky softens shadows")
	t.check(float(rain["opacity"]) < float(noon["opacity"]),
		"clouds reduce harsh direct-sun shadow contrast")
	t.check(float(rainy_dusk["opacity"]) < float(dusk["opacity"]),
		"cloudy dusk has softer shadow contrast than clear dusk")
	t.check(float(rainy_dusk["blur"]) >= float(rain["blur"]),
		"sunset clouds cannot decrease soft-shadow width")
	t.check(float(rainy_dusk["blur"]) <= float(noon["blur"]) * 1.5,
		"shadow blur never grows unbounded")
	var moon: Dictionary = Shadow.profile(3, 0.0, -0.7, 0.0)
	t.check(float(moon["opacity"]) < float(noon["opacity"]),
		"moon shadows are gentler than direct sunlight")

	t.current = "low-end maintains the exact fixed original shadow budget"
	for quality in [0, 1]:
		for weather in [0.0, 0.5, 1.0]:
			var p: Dictionary = Shadow.profile(quality, 0.5, 0.12, weather)
			t.near(float(p["blur"]),
				float(Lighting.settings(quality, "gl_compatibility")["shadow_blur"]),
				0.0001, "low-end keeps the existing renderer blur")
			t.eq(float(p["opacity"]), 1.0,
				"low-end does not schedule expensive atmospheric soft shadows")
	for quality in 4:
		for day in [0.0, 0.5, 1.0]:
			for storm in [0.0, 0.5, 1.0]:
				var p: Dictionary = Shadow.profile(quality, day, 0.3, storm)
				t.check(is_finite(float(p["blur"])) and float(p["blur"]) >= 1.0,
					"all weather and quality settings have finite shadow blur")
				t.check(float(p["opacity"]) >= 0.4 and float(p["opacity"]) <= 1.0,
					"all weather and quality settings have bounded shadow opacity")
	t.eq(Shadow.profile(3, NAN, 0.1, 0.5)["opacity"], 1.0,
		"bad daylight fails safe")
	t.eq(Shadow.profile(3, 0.9, INF, 0.5)["opacity"], 1.0,
		"bad sun elevation fails safe")
	t.eq(Shadow.profile(3, 0.9, 0.5, NAN)["opacity"], 1.0,
		"bad storm state fails safe")

	t.current = "actual Godot DirectionalLight3D and shared live client"
	var sun := DirectionalLight3D.new()
	Lighting.apply(sun, null, 3, "forward_plus")
	# A separate 5 Hz system owns weather shadow contrast. Changing the
	# 4 Hz penumbra must never overwrite its most recent opacity value.
	sun.shadow_opacity = 0.62
	Shadow.apply(sun, 3, 1.0, 0.8, 0.0)
	t.near(sun.shadow_opacity, 0.62, 0.001,
		"penumbra update preserves the existing cloud-shadow contrast")
	var old_blur: float = sun.shadow_blur
	Shadow.apply(sun, 3, 0.6, 0.1, 1.0)
	t.check(sun.shadow_blur > old_blur,
		"real Godot sun shadow filter softens at overcast dusk")
	t.near(sun.shadow_opacity, 0.62, 0.001,
		"changing weather penumbra does not fight the opacity controller")
	Shadow.apply(sun, 1, 0.6, 0.1, 1.0)
	t.near(sun.shadow_opacity, 0.62, 0.001,
		"downgrading penumbra keeps independently configured light contrast")
	t.near(sun.shadow_blur, 1.0, 0.001,
		"downgrading restores original fixed shadow blur")
	Shadow.apply(null, 3, 0.5, 0.1, 0.5)
	t.check(true, "null light is safely ignored")
	sun.free()
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(atmosphere.contains("SunShadowAtmosphere.apply(sun,"),
		"online and solo use the integrated shared atmosphere")
	t.check(atmosphere.contains("SunShadowQuality.update_opacity(sun,"),
		"weather shadow contrast still follows the existing 5 Hz path")
	t.check(not (Shadow as Script).source_code.contains("sun.shadow_opacity ="),
		"penumbra module never overwrites weather opacity")
	t.check(atmosphere.contains("SHADOW_FILTER_INTERVAL := 0.25"),
		"native light parameters update only four times per second")
	t.check(atmosphere.contains("_shadow_filter_level = clampi("),
		"runtime graphics quality invalidates lighting profiles")
	t.check((Quality as Script).source_code.contains(
		'atmosphere.call("apply_graphics_profile", atmosphere_profile)'),
		"existing runtime quality controller propagates to live light")
