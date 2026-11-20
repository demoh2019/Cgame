extends RefCounted
## Native engine precomputes HDR sky optical depth. Stock Godot is safe.

const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "optical-depth sky quality budgets"
	var p0: Dictionary = Profiles.settings(0)
	var p1: Dictionary = Profiles.settings(1)
	var p2: Dictionary = Profiles.settings(2)
	var p3: Dictionary = Profiles.settings(3)
	t.eq(float(p0["atmospheric_lut_strength"]), 0.0, "Performance skips all sky LUT sampling")
	t.eq(float(p1["atmospheric_lut_strength"]), 0.0, "Balanced keeps cached sky")
	t.check(float(p2["atmospheric_lut_strength"]) > 0.0, "High gains spectral atmosphere")
	t.check(float(p3["atmospheric_lut_strength"]) > float(p2["atmospheric_lut_strength"]),
		"Ultra uses full cinematic atmospheric color")
	t.check(float(p3["atmospheric_lut_strength"]) <= 1.0, "sky strength bounded")
	t.current = "sky material quality integration"
	var shader := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(shader != null, "game atmospheric sky imports")
	if shader != null:
		t.check(shader.code.contains("atmospheric_lut") and shader.code.contains("optical.a"),
			"shader combines spectral in-scattering and transmittance")
		t.check(shader.code.contains("has_atmospheric_lut && atmospheric_lut_strength > 0.001"),
			"low-end sky does not sample optional LUT")
		t.check(shader.code.contains("AT_CUBEMAP_PASS"), "reflection path remains compatible")
	var atmo_code: String = (Atmosphere as Script).source_code
	t.check(atmo_code.contains('ClassDB.class_exists("SkyScatteringLUT")'),
		"stock Godot gracefully skips custom native module")
	t.check(atmo_code.contains('set_shader_parameter("solar_elevation"'),
		"sun height is uploaded at bounded sky refresh cadence")
	t.check(atmo_code.contains('set_shader_parameter("has_atmospheric_lut"'),
		"shader samples the LUT only after native initialization")
	t.check((Quality as Script).source_code.contains(
		'atmosphere_profile["atmospheric_lut_strength"]'),
		"game graphic profiles actually reach sky")
	if ClassDB.class_exists("SkyScatteringLUT"):
		var generator: Object = ClassDB.instantiate("SkyScatteringLUT")
		var image: Image = generator.call("generate_lut", 64, 32, 2.0) as Image
		t.check(image != null, "native generator returns an image")
		if image != null:
			t.eq(image.get_width(), 64, "native image uses requested width")
			t.eq(image.get_height(), 32, "native image uses requested height")
			t.eq(image.get_format(), Image.FORMAT_RGBAH, "linear floating HDR LUT format")
			var top := image.get_pixel(63, 31)
			var low := image.get_pixel(0, 31)
			t.check(top.b > top.r, "zenith scattering emphasizes blue wavelengths")
			t.check(low.a < top.a, "horizon has lower optical transmittance")
