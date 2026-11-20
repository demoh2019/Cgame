extends RefCounted
## Verify expensive directional PCSS is opt-in and weather contrast stays bounded.
const SunShadows = preload("res://scripts/client/sun_shadow_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "renderer-aware directional shadow cost"
	for method in ["gl_compatibility", "mobile", "unknown"]:
		for tier in 4:
			var p: Dictionary = SunShadows.settings(tier, method)
			t.eq(p["pcss"], false, "non-Forward+ never pays for PCSS")
			t.near(float(p["angular_distance"]), 0.0, 0.0001,
				"non-Forward+ uses inexpensive shadow mapping")
	for tier in [0, 1]:
		t.eq(SunShadows.settings(tier, "forward_plus")["pcss"], false,
			"Performance and Balanced avoid costly PCSS")
		t.near(float(SunShadows.settings(tier, "forward_plus")["angular_distance"]),
			0.0, 0.0001, "no angular shadow filter on low profile")
	var high: Dictionary = SunShadows.settings(2, "forward_plus")
	var ultra: Dictionary = SunShadows.settings(3, "forward_plus")
	t.eq(high["pcss"], true, "High retains contact-hardening shadow quality")
	t.eq(ultra["pcss"], true, "Ultra retains contact-hardening shadow quality")
	t.check(float(ultra["angular_distance"]) > float(high["angular_distance"]),
		"Ultra receives more natural soft penumbrae")
	t.check(float(ultra["angular_distance"]) <= 0.55,
		"solar angular size stays physically plausible")
	t.eq(SunShadows.settings(-20, "forward_plus"),
		SunShadows.settings(0, "forward_plus"), "profile clamps below range")
	t.eq(SunShadows.settings(99, "forward_plus"),
		SunShadows.settings(3, "forward_plus"), "profile clamps above range")

	t.current = "directional shadow contrast follows daylight and storms"
	var noon: float = SunShadows.opacity(1.0, 0.9, 0.0)
	var sunrise: float = SunShadows.opacity(0.40, 0.10, 0.0)
	var moon: float = SunShadows.opacity(0.0, -0.3, 0.0)
	var storm: float = SunShadows.opacity(1.0, 0.9, 1.0)
	t.check(noon > sunrise and sunrise > moon,
		"midday shadows are stronger than dusk and moon shadows")
	t.check(storm < noon, "thick storm clouds diffuse directional shadows")
	t.check(storm > 0.10 and moon >= 0.20,
		"even storm and moonlight retain readable forms")
	t.near(SunShadows.opacity(-5.0, -0.3, -10.0), moon, 0.0001,
		"invalid negative daylight and storm clamp")
	t.near(SunShadows.opacity(20.0, 0.9, 15.0), storm, 0.0001,
		"over-range daylight and storm clamp")
	t.near(SunShadows.opacity(NAN, 0.8, 0.0), 0.58, 0.0001,
		"invalid daylight never injects NaN into native shadows")
	t.near(SunShadows.opacity(0.5, INF, 0.2), 0.58, 0.0001,
		"invalid sun elevation keeps a finite shadow contrast")
	t.near(SunShadows.opacity(0.5, 0.8, NAN), 0.58, 0.0001,
		"undefined weather cannot poison the lighting pipeline")
	for amount in 11:
		var alpha: float = SunShadows.opacity(0.55, 0.30, float(amount) / 10.0)
		t.check(alpha >= 0.08 and alpha <= 0.96,
			"shadow darkness is within the material range")

	t.current = "shadow policy respects other quality controls"
	var sun := DirectionalLight3D.new()
	sun.shadow_blur = 1.25
	sun.shadow_enabled = true
	SunShadows.apply(sun, 3, "forward_plus", 1.0, 0.9, 0.0)
	t.near(sun.light_angular_distance, 0.53, 0.0001,
		"Ultra sun config applies the 0.53 degree angular source")
	t.near(sun.shadow_opacity, noon, 0.0001,
		"initial contrast follows weather immediately")
	SunShadows.update_opacity(sun, 1.0, 0.9, 1.0)
	t.near(sun.shadow_opacity, storm, 0.0001,
		"live weather changes the existing light shadow opacity")
	SunShadows.apply(sun, 1, "forward_plus", 0.0, -0.3, 0.0)
	t.near(sun.light_angular_distance, 0.0, 0.0001,
		"switching back to Balanced releases PCSS")
	t.near(sun.shadow_blur, 1.25, 0.0001,
		"existing cascade shadow blur is untouched")
	t.eq(sun.shadow_enabled, true,
		"shadow enable is still controlled by the graphics quality manager")
	sun.free()

	t.current = "live day/night atmosphere integration"
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(atmosphere_code.contains("SunShadowQuality.apply(sun,"),
		"quality switch sends renderer-aware PCSS settings to sun")
	t.check(atmosphere_code.contains("SunShadowQuality.update_opacity(sun,"),
		"day/night controller sends weather contrast to existing sun")
	t.check(atmosphere_code.contains("_shadow_elapsed >= 0.20"),
		"shadow opacity changes on a 5 Hz budget instead of every frame")
	t.check(atmosphere_code.contains("sun.light_angular_distance = 0.0"),
		"startup never enables expensive PCSS before applying the preset")


	t.current = "world-locked directional PCSS preserves low-end profile budget"
	var stable_sun := DirectionalLight3D.new()
	SunShadows.apply(stable_sun, 3, "forward_plus", 0.9, 0.6, 0.0)
	var angular: float = stable_sun.light_angular_distance
	var opacity_before: float = stable_sun.shadow_opacity
	SunShadows.apply(stable_sun, 3, "forward_plus", 0.9, 0.6, 0.0)
	t.near(stable_sun.light_angular_distance, angular, 0.0001,
		"reapplying Ultra keeps the same physically sized soft sun")
	t.near(stable_sun.shadow_opacity, opacity_before, 0.0001,
		"reapplying preset does not disturb shadow contrast")
	SunShadows.apply(stable_sun, 0, "forward_plus", 0.9, 0.6, 0.0)
	t.near(stable_sun.light_angular_distance, 0.0, 0.0001,
		"Performance reverts to inexpensive non-PCSS shadow filtering")
	SunShadows.apply(stable_sun, 3, "mobile", 0.9, 0.6, 0.0)
	t.near(stable_sun.light_angular_distance, 0.0, 0.0001,
		"Mobile backend never turns on GPU-heavy PCSS")
	var shadow_code: String = (SunShadows as Script).source_code
	t.check(shadow_code.contains(
		"if not is_equal_approx(sun.light_angular_distance, angular_size):"),
		"sun profile leaves unchanged native shadow-light parameters alone")
	stable_sun.free()
