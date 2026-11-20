extends RefCounted
## Cinematic native glow: sunlit surfaces stay detailed, sunset and
## emissive lights bloom softly, weather and quality bound the GPU cost.
const Bloom = preload("res://scripts/client/cinematic_bloom.gd")
const Grade = preload("res://scripts/client/cinematic_color_grade.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "golden hour and night bloom without faded daytime detail"
	var noon: Dictionary = Bloom.look(3, "forward_plus", 1.0, 0.82, 0.0)
	var dusk: Dictionary = Bloom.look(3, "forward_plus", 0.50, 0.08, 0.0)
	var night: Dictionary = Bloom.look(3, "forward_plus", 0.0, -0.65, 0.0)
	var storm: Dictionary = Bloom.look(3, "forward_plus", 1.0, 0.82, 1.0)
	t.check(float(dusk["intensity"]) > float(noon["intensity"]),
		"sunset scatters warmer bright highlights through existing bloom")
	t.check(float(dusk["threshold"]) < float(noon["threshold"]),
		"low-angle sunlight has more visible light bloom")
	t.check(float(night["threshold"]) < float(noon["threshold"]),
		"torches and lanterns glow without brightening dark background")
	t.check(float(night["bloom"]) >= float(noon["bloom"]),
		"night high-contrast lights have a slightly wider optical halo")
	t.check(float(storm["threshold"]) >= float(noon["threshold"]),
		"diffuse overcast daylight cannot smear every surface into light")
	t.check(float(storm["intensity"]) <= float(noon["intensity"]),
		"overcast rain reduces the glow brightness")
	var high: Dictionary = Bloom.look(2, "forward_plus", 0.5, 0.08, 0.0)
	t.check(float(high["intensity"]) <= float(dusk["intensity"]),
		"High uses less pronounced scattering than Ultra")
	t.check(float(high["threshold"]) >= float(dusk["threshold"]),
		"High keeps brighter threshold to protect fine texture detail")

	t.current = "renderer and quality gates preserve cheaper legacy path"
	for method in ["gl_compatibility", "mobile", ""]:
		for tier in 4:
			var p: Dictionary = Bloom.look(tier, method, 0.5, 0.1, 0.4)
			t.check(not bool(p["premium"]),
				"non-Forward+ renderer uses the original glow optics")
			t.eq(float(p["threshold"]), 1.10,
				"Compatibility keeps original constant threshold")
			t.eq(float(p["bloom"]), 0.06,
				"Compatibility keeps original bloom contribution")
	for tier in [0, 1]:
		var p: Dictionary = Bloom.look(tier, "forward_plus", 0.5, 0.1, 0.4)
		t.check(not bool(p["premium"]),
			"Performance/Balanced never activate more expensive lens settings")
		t.eq(float(p["threshold"]), 1.10,
			"low-end uses fixed HDR threshold")
	for tier in 4:
		for daylight in [0.0, 0.4, 1.0]:
			for storm_amount in [0.0, 0.5, 1.0]:
				var p: Dictionary = Bloom.look(tier, "forward_plus",
					daylight, 0.10, storm_amount)
				t.check(float(p["intensity"]) >= 0.30 and float(p["intensity"]) <= 0.72,
					"intensity stays bounded across all seasons and tiers")
				t.check(float(p["threshold"]) >= 0.94 and float(p["threshold"]) <= 1.32,
					"HDR highlight threshold stays within neutral-safe range")
				t.check(float(p["bloom"]) >= 0.04 and float(p["bloom"]) <= 0.08,
					"native bloom strength stays subtle")

	t.current = "live native Environment changes only necessary parameters"
	var env := Environment.new()
	env.glow_enabled = true
	Bloom.apply(env, 3, "forward_plus", 0.5, 0.08, 0.0)
	t.near(env.glow_intensity, float(dusk["intensity"]), 0.0001,
		"real Godot HDR glow matches Ultra sunset profile")
	t.near(env.glow_hdr_threshold, float(dusk["threshold"]), 0.0001,
		"real engine luminance threshold is updated")
	t.near(env.glow_bloom, float(dusk["bloom"]), 0.0001,
		"real engine controls the already-enabled bloom chain")
	Bloom.apply(env, 3, "forward_plus", 0.5, 0.08, 0.0)
	t.near(env.glow_intensity, float(dusk["intensity"]), 0.0001,
		"identical frame cannot drift additive glow")
	Bloom.apply(env, 1, "gl_compatibility", 1.0, 0.82, 0.0)
	t.near(env.glow_hdr_threshold, 1.10, 0.0001,
		"downgrading restores the original baseline HDR threshold")
	t.near(env.glow_bloom, 0.06, 0.0001,
		"renderer fallback restores baseline bloom strength")
	Bloom.apply(null, 3, "forward_plus", 1.0, 0.8, 0.0)
	t.check(true, "uninitialized world environment safely skips the effect")

	t.current = "single shared weather-driven optical controller, no extra passes"
	var atm_src: String = (Atmosphere as Script).source_code
	t.check(atm_src.contains("CinematicBloom.apply(environment,"),
		"shared online and solo weather rig invokes native cinematic glow")
	t.check(atm_src.contains("BLOOM_INTERVAL := 0.20"),
		"expensive engine glow resource updates are capped to five per second")
	t.check(atm_src.contains("_bloom_elapsed = BLOOM_INTERVAL"),
		"switching renderer or tier invalidates and restores glow quickly")
	var grade_src: String = (Grade as Script).source_code
	t.check(not grade_src.contains('environment.glow_intensity = float(p["glow_intensity"])'),
		"old per-frame glow upload is removed without changing the filmic color curve")
	t.check(grade_src.contains('environment.tonemap_exposure = float(p["exposure"])'),
		"artist-directed native exposure remains frame-synchronized")
	t.check((Quality as Script).source_code.contains(
		'atmosphere.call("apply_graphics_profile", atmosphere_profile)'),
		"Quality presets still reach the shared atmosphere")
	var cpp_src := FileAccess.get_file_as_string("res://tests/test_cinematic_bloom.gd")
	t.check(cpp_src.contains("native Environment"),
		"new native bloom validation suite is on disk")
