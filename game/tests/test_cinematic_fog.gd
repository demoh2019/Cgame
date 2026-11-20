extends RefCounted
## World fog quality remains stable across weather and renderer fallback.

const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "renderer-specific volumetric fog cost gates"
	var lowest: Dictionary = CinematicFog.profile(0, "forward_plus")
	var balanced: Dictionary = CinematicFog.profile(1, "forward_plus")
	var high: Dictionary = CinematicFog.profile(2, "forward_plus")
	var ultra: Dictionary = CinematicFog.profile(3, "forward_plus")
	t.check(not bool(lowest["enabled"]), "Performance never enables expensive volume fog")
	t.check(not bool(balanced["enabled"]), "Balanced keeps one inexpensive height fog")
	t.check(bool(high["enabled"]), "High enables short Forward+ froxel lighting")
	t.check(bool(ultra["enabled"]), "Ultra enables a longer, higher-quality range")
	t.check(float(high["length"]) < float(ultra["length"]),
		"High computes fog in a shorter GPU volume")
	t.check(float(high["base_density"]) < float(ultra["base_density"]),
		"Ultra retains richer near-camera atmosphere")
	t.check(int(high["froxel_size"]) == 112 and int(high["froxel_depth"]) == 96,
		"High saves froxel bandwidth compared with the default 128-cube")
	t.check(int(ultra["froxel_size"]) == 160 and int(ultra["froxel_depth"]) == 128,
		"Ultra improves screen-space volumetric detail without enlarging depth")
	t.check(int(ultra["froxel_size"]) > int(high["froxel_size"]),
		"quality tiers scale the expensive lighting grid")
	t.check(int(lowest["froxel_size"]) == 0 and int(balanced["froxel_size"]) == 0,
		"low-end profiles do not reserve a volumetric grid")
	for renderer in ["gl_compatibility", "mobile", "", "vulkan_compatibility"]:
		for quality in 4:
			t.check(not bool(CinematicFog.profile(quality, renderer)["enabled"]),
				"non-Forward+ renderer never enables unsupported volumetrics")
	t.eq(CinematicFog.profile(-10, "forward_plus")["length"], lowest["length"],
		"negative tier clamps to Performance budget")
	t.eq(CinematicFog.profile(99, "forward_plus")["length"], ultra["length"],
		"oversized tier clamps to Ultra budget")
	var independent: Dictionary = CinematicFog.profile(3, "forward_plus")
	independent["length"] = -100.0
	t.check(float(CinematicFog.profile(3, "forward_plus")["length"]) > 0.0,
		"caller mutation cannot damage the central graphics budget")

	t.current = "sunrise and storms change mist smoothly without new passes"
	var clear: Dictionary = CinematicFog.weather(0.9, 0.8, 0.0, high)
	var sunrise: Dictionary = CinematicFog.weather(0.4, 0.08, 0.0, high)
	var storm: Dictionary = CinematicFog.weather(0.9, 0.8, 1.0, high)
	t.check(float(clear["height_density"]) > 0.0,
		"natural sea-level haze remains visible without a high-end GPU")
	t.check(float(sunrise["height_density"]) > float(clear["height_density"]),
		"early sun increases low-lying mist density")
	t.check(float(storm["height_density"]) > float(clear["height_density"]),
		"rain gradually increases atmosphere density")
	t.check(float(storm["volume_density"]) > float(clear["volume_density"]),
		"Forward+ storm adds denser light scattering")
	t.check(float(sunrise["sun_scatter"]) > float(clear["sun_scatter"]),
		"low sun enhances dawn haze")
	t.check(float(sunrise["anisotropy"]) > float(clear["anisotropy"]),
		"low sun increases forward scattering and cinematic light shafts")
	t.check(float(storm["anisotropy"]) < float(clear["anisotropy"]),
		"storm droplets soften shafts instead of boosting forward scattering")
	for sky_frame in [clear, sunrise, storm]:
		t.check(float(sky_frame["anisotropy"]) >= 0.24
			and float(sky_frame["anisotropy"]) <= 0.55,
			"physical fog phase asymmetry stays within a bounded GPU-safe range")
	t.eq(CinematicFog.weather(1.0, 0.5, 1.0, balanced)["volume_density"], 0.0,
		"Balanced never burns GPU time on volumetric fog")
	t.eq(CinematicFog.weather(1.0, 0.5, 1.0, CinematicFog.profile(3, "gl_compatibility"))["volume_density"], 0.0,
		"Compatibility retains only low-cost fog even on Ultra")
	for q in 4:
		var p: Dictionary = CinematicFog.profile(q, "forward_plus")
		for day in [0.0, 0.4, 1.0]:
			for weather_amount in [0.0, 0.5, 1.0]:
				var f: Dictionary = CinematicFog.weather(day, 0.1, weather_amount, p)
				t.check(float(f["height_density"]) >= 0.0 and
					float(f["height_density"]) <= CinematicFog.MAX_HEIGHT_DENSITY,
					"height density is finite, non-negative and bounded")
				t.check(float(f["volume_density"]) >= 0.0 and
					float(f["volume_density"]) <= CinematicFog.MAX_VOLUME_DENSITY,
					"GPU volume density is bounded for all weather and light values")

	t.current = "live environment changes without duplicating fog volumes"
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	CinematicFog.apply_profile(env, sun, high)
	t.check(env.volumetric_fog_enabled, "high-end volume is enabled on Forward+")
	t.near(env.volumetric_fog_length, high["length"], 0.0001,
		"screen-aligned volume has the budgeted short range")
	t.check(env.volumetric_fog_temporal_reprojection_enabled,
		"temporal reprojection smooths low-resolution froxels")
	t.check(env.volumetric_fog_temporal_reprojection_amount < 0.9,
		"history blend is limited to avoid ghost trails")
	t.eq(env.volumetric_fog_gi_inject, 0.0,
		"no expensive indirect-light injection runs when not requested")
	t.eq(sun.light_volumetric_fog_energy, 0.8,
		"sun participates in scattering without increasing light count")
	CinematicFog.apply_weather(env, 0.4, 0.08, 1.0, high, Color(0.4, 0.5, 0.6))
	t.near(env.volumetric_fog_anisotropy,
		float(CinematicFog.weather(0.4, 0.08, 1.0, high)["anisotropy"]),
		0.011, "live sun shafts follow the smoothed physical scattering phase")
	t.near(env.volumetric_fog_density,
		float(CinematicFog.weather(0.4, 0.08, 1.0, high)["volume_density"]),
		0.000001, "live storm density matches pure weather rules")
	t.check(env.fog_height_density > 0.0,
		"low-cost fallback haze remains active near sea level")
	t.check(env.fog_sun_scatter >= 0.0, "sun shafts stay physically non-negative")
	CinematicFog.apply_profile(env, sun, balanced)
	t.check(not env.volumetric_fog_enabled, "dropping quality disables volumetric pass")
	t.eq(env.volumetric_fog_density, 0.0,
		"disabled volumetric data cannot continue scattering light")
	t.eq(sun.light_volumetric_fog_energy, 0.0,
		"fallback avoids even the sun's volumetric contribution")
	CinematicFog.apply_weather(env, 1.0, 0.8, 0.3, balanced, Color.WHITE)
	t.check(env.fog_height_density > 0.0,
		"fallback still renders compatible world atmosphere")
	sun.free()

	t.current = "graphics quality reports the real rendering method to atmosphere"
	var graphics: String = FileAccess.get_file_as_string(
		"res://scripts/client/graphics_quality.gd")
	t.check(graphics.contains("atmosphere_profile[\"quality_level\"] = _level"),
		"preset changes propagate the actual selected graphics tier")
	t.check(graphics.contains("atmosphere_profile[\"rendering_method\"] = method"),
		"renderer fallback propagates to the same atmospheric pipeline")
	var atmosphere: String = FileAccess.get_file_as_string(
		"res://scripts/client/atmosphere.gd")
	t.check(atmosphere.contains("CinematicFog.apply_profile"),
		"live weather rig updates GPU budget when quality changes")
	t.check(atmosphere.contains("CinematicFog.apply_weather"),
		"day/night and rain update actual fog resources")
	var fog_script: String = FileAccess.get_file_as_string("res://scripts/client/cinematic_fog.gd")
	t.check(fog_script.contains("RenderingServer.environment_set_volumetric_fog_volume_size("),
		"quality presets control native engine froxel allocation on Forward+")
	t.check(fog_script.contains('if enabled:\n\t\t# Match HDRP'),
		"Compatibility and low-end tiers never allocate the high-end fog grid")
	t.check(not bool(GraphicsQuality.profile(0)["ssao"]),
		"low-end graphics retains other existing low-cost postprocessing choices")
