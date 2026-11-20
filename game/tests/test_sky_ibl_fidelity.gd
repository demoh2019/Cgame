extends RefCounted
## Native Godot sky lighting prefilter and cached refresh budgets.
## All tiers preserve sunset/weather/lunar shader paths and server state.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")

func run(t) -> void:
	t.current = "high fidelity sky IBL cubemap budgets"
	var previous_resolution: int = 0
	var previous_cadence: float = 99.0
	for tier in 4:
		var profile: Dictionary = VisualProfiles.settings(tier)
		var resolution: int = int(profile["sky_radiance"])
		var cadence: float = float(profile["sky_refresh_interval"])
		t.check(resolution >= previous_resolution, "sky resolution increases with tier")
		t.check(cadence < previous_cadence and cadence >= 0.5,
			"all tiers refresh at bounded and ordered frequency")
		previous_resolution = resolution
		previous_cadence = cadence
	t.eq(VisualProfiles.settings(2)["sky_radiance"], 128,
		"High uses 128 sky radiance for natural glossy PBR")
	t.eq(VisualProfiles.settings(3)["sky_radiance"], 256,
		"Ultra uses 256 high fidelity sky radiance")
	t.check(VisualProfiles.settings(3)["sky_refresh_interval"] >= 0.65,
		"Ultra avoids reconstructing a 256 cubemap every frame")
	t.current = "native renderer and in-game controllers"
	var source: String = (Atmosphere as Script).source_code
	t.check(source.contains("Sky.RADIANCE_SIZE_256"),
		"sky renderer handles Ultra native cube resolution")
	var quality: String = (GraphicsQuality as Script).source_code
	t.check(quality.contains('atmosphere_profile["sky_radiance"] = world_profile["sky_radiance"]'),
		"game graphics preset controls real sky cubemap")
	var config: String = FileAccess.get_file_as_string("res://project.godot")
	t.check(config.contains("reflections/sky_reflections/ggx_samples=48"),
		"engine GGX prefilter uses 48 samples on desktop")
	t.check(config.contains("reflections/sky_reflections/ggx_samples.mobile=16"),
		"mobile filtering stays inexpensive")
	t.check(not config.contains("rendering/environment/ssil/half_size=true"),
		"project renderer settings do not repeat their section prefix")
