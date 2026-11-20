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

	t.current = "conservative volumetric cloud density guards"
	if sky != null:
		var cloud_source: String = sky.code
		t.check(cloud_source.contains("float cloud_threshold = 1.0 - coverage;"),
			"raymarch uses the same exact cloud coverage threshold")
		t.check(cloud_source.contains("if (broad + 0.45 <= cloud_threshold)"),
			"first octave cheaply excludes guaranteed-empty cloud regions")
		t.check(cloud_source.contains("if (broad + medium + 0.17 <= cloud_threshold)"),
			"second octave can exclude a region before expensive fine noise")
		t.check(cloud_source.contains("if (base <= cloud_threshold)"),
			"high-frequency edge erosion cannot run outside actual cloud density")
		t.check(cloud_source.contains("if (h <= 0.0 || h >= 1.0)"),
			"the empty top and bottom of the slab skip all density noise")
		t.check(cloud_source.contains("bool cloud_sunlit = dot(sun_l, sun_l) > 0.0001;"),
			"nighttime ambient clouds skip irrelevant direct-shadow rays")
		t.check(cloud_source.contains("if (cloud_sunlit)") and
			cloud_source.contains("for (int k = 1; k <= 3; k++)"),
			"daytime clouds preserve original three-point self-shadowing")
		t.check(cloud_source.contains("if (trans < 0.02)") and
			cloud_source.contains("int steps = AT_CUBEMAP_PASS ?"),
			"original early ray termination and lower-cost reflection probes remain")
		t.check(not cloud_source.contains("return;"),
			"no forbidden early return inside the Godot sky processor")
	# This is a deterministic *conservative upper bound*, not an artistic
	# approximation: omitted noise octaves cannot exceed their coefficients.
	for coverage in [0.05, 0.45, 0.70, 0.98]:
		var threshold: float = 1.0 - coverage
		for n0 in [0.0, 0.2, 0.6, 1.0]:
			for n1 in [0.0, 0.4, 1.0]:
				for n2 in [0.0, 0.6, 1.0]:
					var broad: float = n0 * 0.55
					var medium: float = n1 * 0.28
					var fine: float = n2 * 0.17
					if broad + 0.45 <= threshold:
						t.check(broad + medium + fine <= threshold + 0.000001,
							"coarse conservative bound cannot cull a visible cloud")
					if broad + medium + 0.17 <= threshold:
						t.check(broad + medium + fine <= threshold + 0.000001,
							"medium conservative bound cannot cull a visible cloud")

	t.current = "native sky radiance reuse under adaptive quality"
	var cached_sky := Sky.new()
	var desired: int = Sky.RADIANCE_SIZE_128
	if cached_sky.has_method("configure_render_budget"):
		cached_sky.call("configure_render_budget", desired, Sky.PROCESS_MODE_INCREMENTAL)
		cached_sky.call("configure_render_budget", desired, Sky.PROCESS_MODE_INCREMENTAL)
	else:
		cached_sky.radiance_size = desired
		cached_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	t.eq(cached_sky.radiance_size, desired,
		"native fork and stock fallback select the same radiance budget")
	t.eq(cached_sky.process_mode, Sky.PROCESS_MODE_INCREMENTAL,
		"all graphics tiers retain incremental reflection cubemap filtering")
	var atmo_source: String = (Atmosphere as Script).source_code
	t.check(atmo_source.contains('sky.has_method("configure_render_budget")') and
		atmo_source.contains('sky.radiance_size != desired_radiance'),
		"quality switches avoid redundant native and stock Godot cubemap resizing")

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
