extends SceneTree
## Lightweight graphics-only checks for CI:
## godot --headless --path game --script res://tests/run_graphics.gd
## No network, GPU, downloaded model packs or long gameplay simulation needed.

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_graphics_lightning_flash.gd",
	"res://tests/test_sky_lighting_budget.gd",
	"res://tests/test_rain_vfx.gd",
	"res://tests/test_footprint_decals.gd",
	"res://tests/test_puddle_ripples.gd",
	"res://tests/test_terrain_height_blend.gd",
	"res://tests/test_water_caustics.gd",
	"res://tests/test_weather_cloud_advection.gd",
	"res://tests/test_graphics_quality.gd",
	"res://tests/test_cinematic_bloom.gd",
	"res://tests/test_foliage_spectral_optics.gd",
	"res://tests/test_graphics_auto_quality.gd",
	"res://tests/test_graphics_texture_streaming.gd",
	"res://tests/test_terrain_antitiling.gd",
	"res://tests/test_graphics_native_specular_aa.gd",
	"res://tests/test_storm_lightning.gd",
]


func _initialize() -> void:
	var total_checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s: missing or invalid script" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		var started := Time.get_ticks_msec()
		suite.run(t)
		total_checks += t.checks
		failures.append_array(t.failures)
		print("%-36s %4d checks, %3d failed, %4d ms" %
			[path.get_file(), t.checks, t.failures.size(),
			Time.get_ticks_msec() - started])
	for failure in failures:
		printerr("FAIL " + failure)
	print("GRAPHICS TOTAL: %d checks, %d failures" %
		[total_checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
