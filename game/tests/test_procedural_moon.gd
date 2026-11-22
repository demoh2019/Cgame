extends RefCounted
## Shared-world moon shading, procedural crescent and quality-tier scalability.
const MoonVisuals = preload("res://scripts/client/moon_visuals.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const OnlineClient = preload("res://scripts/client/online_main.gd")


func run(t) -> void:
	t.current = "authoritative lunar cycle"
	var period: float = WorldCycle.DAY_LENGTH * MoonVisuals.SYNODIC_DAYS
	t.near(MoonVisuals.phase_at(0.0), 0.5, 0.000001,
			"a new world starts under the full moon")
	t.near(MoonVisuals.phase_at(period * 0.5), 0.0, 0.000001,
			"half the synodic month later is a new moon")
	t.near(MoonVisuals.phase_at(period), MoonVisuals.phase_at(0.0),
			0.000001, "lunar cycle repeats without drifting")
	t.near(MoonVisuals.phase_at(WorldCycle.DAY_LENGTH * 0.3),
			MoonVisuals.phase_at(WorldCycle.DAY_LENGTH * 0.3), 0.000001,
			"all clients derive one moon phase from the same world time")
	t.near(MoonVisuals.phase_at(INF), 0.5, 0.000001,
			"invalid network time yields safe artistic fallback")
	t.near(MoonVisuals.illuminated_fraction(0.0), 0.0, 0.000001,
			"new moon is unilluminated")
	t.near(MoonVisuals.illuminated_fraction(0.25), 0.5, 0.000001,
			"first quarter has half the visible surface illuminated")
	t.near(MoonVisuals.illuminated_fraction(0.5), 1.0, 0.000001,
			"full moon is bright")
	t.near(MoonVisuals.illuminated_fraction(0.75), 0.5, 0.000001,
			"last quarter is half illuminated")
	t.check(MoonVisuals.directional_fill(0.0) >= 0.65
			and MoonVisuals.directional_fill(0.5) > MoonVisuals.directional_fill(0.0),
			"moon phase varies directional fill while nights remain readable")

	t.current = "moon shader quality, antialiasing and reflected radiance"
	var moon_details := []
	for level in 4:
		var detail: float = float(VisualProfiles.settings(level)["moon_detail_strength"])
		t.check(detail >= 0.0 and detail <= 1.0, "quality budget for crater detail is bounded")
		moon_details.append(detail)
	t.near(float(moon_details[0]), 0.0, 0.000001,
			"Performance skips tiny crater calculations")
	t.check(float(moon_details[3]) > float(moon_details[2])
			and float(moon_details[2]) > float(moon_details[1]),
			"more powerful GPUs retain more lunar surface detail")
	var source: String = FileAccess.get_file_as_string("res://assets/shaders/sky.gdshader")
	t.check(source.contains("uniform float moon_phase")
			and source.contains("uniform float moon_detail_strength"),
			"sky accepts time-synchronized moon and optional crater quality")
	t.check(source.contains("float terminator = cos(angle)")
			and source.contains("side * lunar_uv.x - terminator"),
			"moon shadow curve produces waxing and waning lunar phases")
	t.check(source.contains("fwidth(lunar_uv)")
			and source.contains("lunar_disc"),
			"moon silhouette uses anti-aliasing and stays rounded")
	t.check(source.contains("earthshine")
			and source.contains("crater_shading"),
			"moon shading includes subtle dark-face glow and lunar maria")
	t.check(source.contains("day_disc")
			and source.contains("daylight < 0.20"),
			"night moon replaces rather than duplicates the sun disc")
	t.check(source.contains("if (use_cached_radiance && !AT_CUBEMAP_PASS)")
			and source.contains("COLOR = color;"),
			"radiance fast path and High/Ultra sky reflection are preserved")
	t.check(not source.contains("return;"), "sky() keeps valid Godot control flow")

	t.current = "live game visuals use the same server clock"
	var graphics: String = (GraphicsQuality as Script).source_code
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(graphics.contains(
			'atmosphere_profile["moon_detail_strength"] = world_profile["moon_detail_strength"]'),
			"graphics preset propagates crater detail")
	t.check(atmosphere.contains('set_shader_parameter("moon_phase", moon_phase)')
			and atmosphere.contains('MoonVisuals.directional_fill(moon_phase)'),
			"sky disc and moonlight respond to the same phase")
	t.check((OnlineClient as Script).source_code.contains("MoonVisuals.phase_at(clock)"),
			"multiplayer sky uses authoritative server time")
