extends RefCounted
## Refined high-end night sky: sparse analytic aurora behind actual clouds.
const SkyAurora = preload("res://scripts/client/sky_aurora.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	test_milky_way(t)
	t.current = "renderer and biome gated aurora quality budgets"
	t.near(SkyAurora.strength(3, 0.0, 0.0), 0.65, 0.0001,
		"Ultra keeps bright but bounded aurora at a clear mountain night")
	t.near(SkyAurora.strength(2, 0.0, 0.0), 0.30, 0.0001,
		"High uses a noticeably lower animation and brightness budget")
	t.eq(SkyAurora.strength(0, 0.0, 0.0), 0.0,
		"Performance skips the expensive sky branch")
	t.eq(SkyAurora.strength(1, 0.0, 0.0), 0.0,
		"Balanced skips all aurora fragment work")
	for method in ["mobile", "gl_compatibility", ""]:
		t.eq(SkyAurora.strength(3, 0.0, 0.0, "mountain", method), 0.0,
			"only Forward+ compiles the visible aurora effect")
	for biome in ["plains", "forest", "swamp", "beach"]:
		t.eq(SkyAurora.strength(3, 0.0, 0.0, biome), 0.0,
			"nonmountain skies remain neutral and preserve stars")
	t.eq(SkyAurora.strength(3, 1.0, 0.0), 0.0,
		"bright daytime sky has no aurora")
	t.eq(SkyAurora.strength(3, 0.0, 1.0), 0.0,
		"heavy cloud storms hide all curtains")
	t.eq(SkyAurora.strength(3, 0.24, 0.0), 0.0,
		"daylight transition reaches exactly zero")
	t.eq(SkyAurora.strength(3, 0.0, 0.8), 0.0,
		"rain transition reaches exactly zero")
	var partial: float = SkyAurora.strength(3, 0.12, 0.18)
	t.check(partial > 0.0 and partial < 0.65,
		"daylight and storm smoothly attenuate aurora without popping")
	for broken in [NAN, INF, -INF]:
		t.eq(SkyAurora.strength(3, broken, 0.0), 0.0,
			"invalid sky time cannot produce NaN RGB")
		t.eq(SkyAurora.strength(3, 0.0, broken), 0.0,
			"invalid weather cannot produce NaN RGB")

	t.current = "cloud compositing and bounded GPU fragment cost"
	var shader := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(shader != null, "real Godot sky shader loads")
	if shader != null:
		var code: String = shader.code
		var first: int = code.find("if (aurora_strength > 0.001")
		var clouds: int = code.find("if (cirrus_detail > 0")
		var cumulonimbus: int = code.find("if (volumetric_cloud_steps > 0")
		t.check(first >= 0 and first < clouds and clouds < cumulonimbus,
			"aurora lies below cirrus and volumetric clouds in actual sky")
		t.check(code.contains("!AT_CUBEMAP_PASS"),
			"expensive aurora emission never contaminates physical sky IBL")
		t.check(code.contains("float emission = (curtain * strands"),
			"few analytic folds replace previous six-layer 3D noise loop")
		t.check(code.contains("color += spectral * emission"),
			"the gradient produces genuine green/violet curtain radiance")
		t.check(not code.contains("for (int i = 0; i < 6; i++)"),
			"old six-sample noise ray march has been removed")
		t.check(not code.contains("sin(TIME"),
			"clock stays cached and does not retrigger radiance every frame")
		t.check(not code.get_slice("void sky() {", 1).contains("return;"),
			"no illegal return in Godot sky processor")

	t.current = "shared sky renderer on online and local game modes"
	var world: String = (Atmosphere as Script).source_code
	t.check(world.contains(
		'SkyAurora.strength(_shadow_filter_level, daylight, storm, biome,'),
		"actual world controller sends biome to the shader")
	t.check(world.contains("_bloom_method))"),
		"active rendering backend suppresses unsupported aurora")
	t.check(world.contains("_sky_refresh_elapsed >= _sky_refresh_interval"),
		"new sky shader reuses bounded cached sky refresh interval")
	t.check((Quality as Script).source_code.contains(
		'Atmosphere') and world.contains("func update("),
		"the existing graphics quality and atmosphere services remain wired")


func test_milky_way(t) -> void:
	t.current = "milky way on dark clear High/Ultra nights"
	t.check(SkyAurora.milky_way_strength(3, 0.0, 0.0, 0.0) > 0.99, "new moon: full band")
	t.check(SkyAurora.milky_way_strength(3, 0.0, 0.0, 0.5) < 0.5, "full moon washes it out")
	t.eq(SkyAurora.milky_way_strength(1, 0.0, 0.0, 0.0), 0.0, "Balanced pays nothing")
