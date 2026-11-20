extends RefCounted
## Sky scattering is a visual-only, zero-texture atmospheric improvement.
## Verify all graphics tiers and actual game controller integration.
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "physically inspired sky quality scale"
	var low: Dictionary = VisualProfiles.settings(0)
	var balanced: Dictionary = VisualProfiles.settings(1)
	var high: Dictionary = VisualProfiles.settings(2)
	var ultra: Dictionary = VisualProfiles.settings(3)
	var strength := []
	for level in 4:
		var value: float = float(VisualProfiles.settings(level)["sky_scattering_strength"])
		t.check(value >= 0.0 and value <= 1.0, "sky aerosol lobe is bounded")
		strength.append(value)
	t.near(float(strength[0]), 0.0, 0.0001,
			"Performance entirely skips extra sky-scattering calculation")
	t.check(float(strength[0]) < float(strength[1])
			and float(strength[1]) < float(strength[2])
			and float(strength[2]) < float(strength[3]),
			"sunset horizon quality increases monotonically")
	t.near(float(strength[3]), 1.0, 0.0001,
			"Ultra shows complete directional aerosol haze")
	t.check(bool(low["sky_use_cached_radiance"]) and bool(balanced["sky_use_cached_radiance"]),
			"Performance/Balanced draw the cached sky instead of recomputing a full-screen panorama")
	t.check(not bool(high["sky_use_cached_radiance"])
			and not bool(ultra["sky_use_cached_radiance"]),
			"High and Ultra keep full-resolution clouds and stars")
	low["sky_scattering_strength"] = 999.0
	t.check(float(VisualProfiles.settings(0)["sky_scattering_strength"]) == 0.0,
			"graphics profiles cannot be modified by external game code")

	t.current = "radiance-safe solar sky shading"
	var sky := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(sky != null, "sky shader imports")
	if sky == null:
		return
	var code: String = sky.code
	t.check(code.contains("uniform float aerosol_scattering_strength"),
			"sky has a shared strength control")
	t.check(code.contains("aerosol_scattering_strength > 0.001")
			and code.contains("daylight > 0.025"),
			"night and low-quality paths skip aerosol math")
	t.check(code.contains("inversesqrt(denom) / denom")
			and code.contains("sunward * horizon_air"),
			"directional Henyey-Greenstein-like sun lobe varies with horizon height")
	t.check(code.contains("atmospheric_visibility")
			and code.contains("storm * 0.88"),
			"storm clouds attenuate bright solar scattering")
	t.check(code.contains("vec3 aerosol_color = mix"),
			"golden-hour aerosol colors blend cool noon and warm sunset")
	t.check(code.contains("sun_direction") and code.contains("AT_CUBEMAP_PASS"),
			"sky reflections share the same scattering as the visible sky")
	t.check(not code.contains("sin(TIME") and not code.contains("TIME * drift")
			and not code.contains("LIGHT0_DIRECTION"),
			"cached sky updates stay bounded rather than triggering every frame")

	t.current = "online renderer passes quality values to atmosphere"
	var controller: String = (GraphicsQuality as Script).source_code
	t.check(controller.contains(
			'atmosphere_profile["sky_scattering_strength"] = world_profile["sky_scattering_strength"]'),
			"preset actually sends aerosol strength to live atmosphere")
	t.check(controller.contains(
			'atmosphere_profile["sky_use_cached_radiance"] = world_profile["sky_use_cached_radiance"]'),
			"existing cached sky setting now reaches the renderer")
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(atmosphere.contains(
			'set_shader_parameter("aerosol_scattering_strength"'),
			"shared day/night system configures shader haze")
	t.check(atmosphere.contains(
			'set_shader_parameter("use_cached_radiance"'),
			"shared sky offers cheaper background reuse on lower tiers")
