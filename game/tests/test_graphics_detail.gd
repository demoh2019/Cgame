extends RefCounted
## Detail budgets are monotonic, safe and independent of the authoritative simulation.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")


func run(t) -> void:
	t.current = "graphics detail budgets"
	var low: Dictionary = VisualProfiles.settings(0)
	var balanced: Dictionary = VisualProfiles.settings(1)
	var high: Dictionary = VisualProfiles.settings(2)
	var ultra: Dictionary = VisualProfiles.settings(3)
	t.eq(VisualProfiles.settings(-200), low, "negative preset clamps")
	t.eq(VisualProfiles.settings(200), ultra, "large preset clamps")
	t.eq(low["water_ripples"], 0.0, "low tier skips animated water normals")
	t.check(ultra["water_ripples"] > high["water_ripples"], "ultra adds water detail")
	t.check(low["grass_fade_end"] < balanced["grass_fade_end"], "low draws shorter grass")
	t.check(balanced["grass_fade_end"] <= high["grass_fade_end"], "high extends grass")
	t.check(high["grass_fade_end"] < ultra["grass_fade_end"], "ultra extends grass farther")
	t.check(low["grass_budget_usec"] <= balanced["grass_budget_usec"], "low limits grass CPU work")
	t.check(high["grass_budget_usec"] <= ultra["grass_budget_usec"], "ultra can grow more tiles per frame")
	t.check(low["chunk_radius"] < high["chunk_radius"], "low streams a smaller world")
	t.check(high["chunk_unload"] > high["chunk_radius"], "high preserves hysteresis to avoid reloading")
	t.check(ultra["chunk_unload"] > ultra["chunk_radius"], "ultra preserves hysteresis")
	t.check(low["sky_radiance"] < ultra["sky_radiance"], "ultra uses higher reflection resolution")
	low["grass_build_radius"] = -999.0
	t.check(VisualProfiles.settings(0)["grass_build_radius"] > 0.0, "profiles cannot be mutated by callers")

	t.current = "screen-space water shader budgets"
	t.check(float(low["water_detail_start"]) < float(low["water_detail_end"]),
		"low water detail distance forms a valid range")
	t.check(float(balanced["water_detail_start"]) < float(balanced["water_detail_end"]),
		"balanced water detail distance forms a valid range")
	t.check(float(high["water_detail_start"]) < float(high["water_detail_end"]),
		"high water detail distance forms a valid range")
	t.check(float(ultra["water_detail_start"]) < float(ultra["water_detail_end"]),
		"ultra water detail distance forms a valid range")
	t.check(float(low["water_detail_end"]) < float(balanced["water_detail_end"]),
		"performance skips distant fine ripples first")
	t.check(float(balanced["water_detail_end"]) < float(high["water_detail_end"]),
		"high has more visible water microdetail than balanced")
	t.check(float(high["water_detail_end"]) < float(ultra["water_detail_end"]),
		"ultra preserves microdetail across longest water vistas")
	var water_shader := load("res://assets/shaders/water.gdshader") as Shader
	t.check(water_shader != null, "actual water shader asset loads")
	if water_shader != null:
		t.check(water_shader.code.contains("detail_fade_start")
			and water_shader.code.contains("detail_fade_end"),
			"water shader exposes both quality-controlled detail distances")
		t.check(water_shader.code.contains("if (edge > 0.001)"),
			"deep-water pixels avoid needless shoreline foam sampling")
