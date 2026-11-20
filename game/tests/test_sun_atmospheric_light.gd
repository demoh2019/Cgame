extends RefCounted
## Native sky transmittance controls real sun light, not only the painted sky.
const Solar = preload("res://scripts/client/solar_irradiance.gd")
const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "solar absorption presets and renderer budget"
	var previous := -1.0
	for tier in 4:
		var strength: float = float(Profiles.settings(tier).get("sun_transmittance_strength", -1.0))
		t.check(is_finite(strength) and strength >= 0.0 and strength <= 1.0,
			"sun transmittance budget stays finite and normalized")
		t.check(strength >= previous, "higher tiers preserve physical illumination")
		previous = strength
	t.eq(float(Profiles.settings(0)["sun_transmittance_strength"]), 0.0,
		"Performance keeps the original white point and moon")
	t.eq(float(Profiles.settings(1)["sun_transmittance_strength"]), 0.0,
		"Balanced keeps artist-directed light color")
	t.check(float(Profiles.settings(2)["sun_transmittance_strength"]) > 0.0,
		"High enables transmittance-coherent direct lighting")
	t.check(float(Profiles.settings(3)["sun_transmittance_strength"]) >
			float(Profiles.settings(2)["sun_transmittance_strength"]),
		"Ultra uses more complete optical attenuation")
	t.check(Solar.supported(0.5, "forward_plus"), "Forward+ uses the new native feature")
	t.check(not Solar.supported(0.0, "forward_plus"),
		"zero strength does not call native code")
	t.check(not Solar.supported(0.9, "gl_compatibility"),
		"Compatibility retains the existing lighting pipeline")
	t.check(not Solar.supported(0.9, "mobile"),
		"Mobile retains the existing lighting pipeline")

	t.current = "optical tint preserves source alpha and white point"
	var artist := Color(1.0, 0.7, 0.45, 0.75)
	var optical := Color(0.73, 0.54, 0.33, 1.0)
	t.eq(Solar.tint(artist, optical, 0.0), artist,
		"legacy sunlight is unchanged when the feature is off")
	t.eq(Solar.tint(artist, optical, -3.0), artist,
		"negative strength never changes lighting")
	var result: Color = Solar.tint(artist, optical, 1.0)
	t.near(result.r, optical.r, 0.0001, "native red extinction becomes direct sunlight")
	t.near(result.g, optical.g, 0.0001, "native green extinction becomes direct sunlight")
	t.near(result.b, optical.b, 0.0001, "native blue extinction becomes direct sunlight")
	t.near(result.a, artist.a, 0.0001, "sun retains original material alpha")
	t.eq(Solar.tint(artist, Color(NAN, 0.0, 0.0), 1.0), artist,
		"corrupt optical samples cannot tint world lighting")
	t.eq(Solar.tint(artist, Color.WHITE, 1.0).r, 1.0,
		"high overhead sunlight stays color-neutral")

	t.current = "live daylight wiring and bounded CPU work"
	var atmo_code: String = (Atmosphere as Script).source_code
	var quality_code: String = (Quality as Script).source_code
	t.check(quality_code.contains('atmosphere_profile["sun_transmittance_strength"]'),
		"actual client applies optical budget to atmosphere controller")
	t.check(atmo_code.contains('"sample_sun_transmittance"'),
		"native atmospheric engine method powers direct sun color")
	t.check(atmo_code.contains("SolarIrradiance.SAMPLE_INTERVAL"),
		"optical CPU computation runs at a bounded cadence")
	t.check(atmo_code.contains("sun.light_color = SolarIrradiance.tint("),
		"sample affects actual scene directional lighting, not just sky pixels")
	t.check(atmo_code.contains("if sun_height < 0.0:"),
		"moon fill is independent of solar attenuation")
	t.check(atmo_code.contains('has_method("sample_sun_transmittance")'),
		"stock Godot and older engine builds fall back safely")
	if ClassDB.class_exists("SkyScatteringLUT"):
		var generator: Object = ClassDB.instantiate("SkyScatteringLUT")
		if generator != null and generator.has_method("sample_sun_transmittance"):
			var zenith: Color = generator.call("sample_sun_transmittance", 1.0, 2.0)
			var horizon: Color = generator.call("sample_sun_transmittance", 0.0, 2.0)
			t.check(Solar.valid(zenith) and Solar.valid(horizon),
				"native direct optical RGB is valid")
			t.near(zenith.r, 1.0, 0.0001, "zenith red keeps calibrated intensity")
			t.near(zenith.g, 1.0, 0.0001, "zenith green keeps calibrated intensity")
			t.near(zenith.b, 1.0, 0.0001, "zenith blue keeps calibrated intensity")
			t.check(horizon.r > horizon.g and horizon.g > horizon.b,
				"sunrise sunlight physically warms while passing through haze")
