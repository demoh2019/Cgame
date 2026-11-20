extends RefCounted
## High/Ultra cloud sun lighting uses the same L8 density as world shadows.
const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Clouds = preload("res://scripts/client/cloud_shadow_lut.gd")


func run(t) -> void:
	t.current = "cached cloud shading quality tiers"
	var previous: float = -1.0
	for tier in 4:
		var strength: float = float(Profiles.settings(tier).get("cloud_lighting_strength", -1.0))
		t.check(is_finite(strength) and strength >= 0.0 and strength <= 1.0,
			"cloud slope lighting strength is valid")
		t.check(strength >= previous, "stronger preset keeps optical cloud detail")
		previous = strength
	t.eq(float(Profiles.settings(0)["cloud_lighting_strength"]), 0.0,
		"Performance does not evaluate the cloud lighting")
	t.eq(float(Profiles.settings(1)["cloud_lighting_strength"]), 0.0,
		"Balanced still reuses its existing L8 cloud shape")
	t.check(float(Profiles.settings(2)["cloud_lighting_strength"]) > 0.0,
		"High shades cloud gradients")
	t.check(float(Profiles.settings(3)["cloud_lighting_strength"]) >
		float(Profiles.settings(2)["cloud_lighting_strength"]),
		"Ultra has deeper self-shadow response")

	t.current = "real sky shader shares shadow lookup, avoids raymarch"
	var sky := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(sky != null, "the current sky resource can be loaded")
	if sky != null:
		var source: String = sky.code
		t.check(source.contains("cloud_profile = texture(cloud_lighting_lut, cloud_uv)"),
			"premium path uses one RGBA cloud geometry lookup")
		t.check(source.contains("cloud_profile = vec4(texture(cirrus_lut, cloud_uv).r"),
			"stock-Godot path uses the original L8 lookup")
		t.check(source.contains("cloud_profile.gb") and source.contains("cloud_profile.a"),
			"cloud surface uses baked slopes and self-occlusion")
		t.check(source.contains("sun_direction") and source.contains("sun_color"),
			"sunset colors and actual solar direction shade the clouds")
		t.check(not source.contains("return;"), "sky processor never returns early")
	var atmo: String = (Atmosphere as Script).source_code
	t.check(atmo.contains('"generate_cloud_lighting_lut", CloudShadowLut.build_image()'),
		"sky cloud LUT originates from identical ground-shadow cloud mask")
	t.check(atmo.contains('set_shader_parameter("has_cloud_lighting_lut"'),
		"unsupported engine never samples optional cloud LUT")
	t.check(atmo.contains('set_shader_parameter("cloud_lighting_strength"'),
		"shader detail is controlled by the profile")
	t.check(atmo.contains('!= "forward_plus"'),
		"Compatibility and Mobile skip native cloud lighting")
	t.check((Quality as Script).source_code.contains(
		'atmosphere_profile["cloud_lighting_strength"]'),
		"quality selector drives the real atmospheric sky material")
	t.check(Clouds.build_image() != null, "existing cloud shadow field still builds")

	t.current = "native RGBA field matches real terrain cloud density"
	if ClassDB.class_exists("SkyScatteringLUT"):
		var generator: Object = ClassDB.instantiate("SkyScatteringLUT")
		if generator != null and generator.has_method("generate_cloud_lighting_lut"):
			var image: Image = generator.call(
				"generate_cloud_lighting_lut", Clouds.build_image()) as Image
			t.check(image != null, "native image bake works")
			if image != null:
				t.eq(image.get_format(), Image.FORMAT_RGBA8,
					"one RGBA8 texture is sufficient")
				t.eq(image.get_width(), Clouds.SIZE, "sky and ground tile at same resolution")
				t.eq(image.get_height(), Clouds.SIZE, "sky cloud textures have same periodicity")
				for z in range(0, Clouds.SIZE, 16):
					for x in range(0, Clouds.SIZE, 16):
						var original: float = Clouds.build_image().get_pixel(x, z).r
						var pixel: Color = image.get_pixel(x, z)
						t.near(pixel.r, original, 0.005,
							"cloud optical and shadow density are identical")
						t.check(pixel.a >= 0.34 and pixel.a <= 1.0,
							"cloud self-shadow is bounded even in dense cores")
