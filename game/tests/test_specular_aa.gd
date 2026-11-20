extends RefCounted
## Source-level checks for geometric specular AA; no physical GPU required.

const Quality = preload("res://scripts/client/graphics_quality.gd")
const Foliage = preload("res://scripts/client/foliage.gd")


func run(t) -> void:
	t.current = "per-quality specular AA budgets"
	t.check(ProjectSettings.has_setting("shader_globals/aa_specular_aa_strength"),
		"shared variance uniform is registered")
	var definition: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_specular_aa_strength", {})
	t.eq(str(definition.get("type", "")), "float", "uniform is a float")
	t.near(float(definition.get("value", -1.0)), 0.0, 0.0001,
		"initial state skips additional derivatives")
	var low: Dictionary = Quality.profile(0)
	var mid: Dictionary = Quality.profile(1)
	var high: Dictionary = Quality.profile(2)
	var ultra: Dictionary = Quality.profile(3)
	t.near(float(low["specular_aa_strength"]), 0.0, 0.0001,
		"Performance keeps the cheap roughness path")
	t.near(float(mid["specular_aa_strength"]), 0.0, 0.0001,
		"Balanced keeps the cheap roughness path")
	t.check(float(high["specular_aa_strength"]) > 0.0,
		"High filters moving glossy highlights")
	t.check(float(ultra["specular_aa_strength"]) > float(high["specular_aa_strength"]),
		"Ultra filters more normal variance")
	t.eq(Quality.profile(-123)["specular_aa_strength"], low["specular_aa_strength"],
		"quality settings clamp below range")
	t.eq(Quality.profile(123)["specular_aa_strength"], ultra["specular_aa_strength"],
		"quality settings clamp above range")

	t.current = "material variance filter"
	var inc: String = FileAccess.get_file_as_string("res://assets/shaders/specular_aa.gdshaderinc")
	t.check(not inc.is_empty(), "specular helper exists")
	t.check(inc.contains("aa_specular_aa_strength <= 0.001"),
		"zero-strength early return avoids fragment derivatives")
	t.check(inc.contains("dFdx(n)") and inc.contains("dFdy(n)"),
		"shading normal derivatives reveal subpixel microgeometry")
	t.check(inc.contains("base * base + added_variance"),
		"variance can only broaden, never sharpen, highlights")
	t.check(inc.contains("min(normal_variance * aa_specular_aa_strength, 0.075)"),
		"roughness increase is capped")
	var terrain := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(terrain != null, "ground shader loads")
	if terrain != null:
		var code: String = terrain.code
		t.check(code.contains("specular_aa.gdshaderinc"),
			"terrain shares filtering implementation")
		t.check(code.contains("filter_specular_roughness(final_roughness, bent)"),
			"normal-mapped soil, cliffs and puddles use filtering")
		t.check(code.contains("puddle * 0.9"), "existing rain puddles remain")
	t.check(Foliage.SHADER_CODE.contains("specular_aa.gdshaderinc"),
		"foliage shares filtering implementation")
	t.check(Foliage.SHADER_CODE.contains("aa_filter_normal"),
		"leaf normal-map variation drives the filter")
	t.check(Foliage.SHADER_CODE.contains("filter_specular_roughness("),
		"bark and leaf highlights receive anti-aliasing")
	t.check(Foliage.SHADER_CODE.contains("ALPHA_SCISSOR_THRESHOLD"),
		"alpha cutouts and silhouette rendering remain")
	t.check((Quality as Script).source_code.contains(
		'global_shader_parameter_set(&"aa_specular_aa_strength"'),
		"graphics preset changes broadcast shared budget")
