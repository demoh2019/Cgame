extends RefCounted
## Height-aware PBR ground blending without new texture or draw-pass cost.
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func _sculpt_natural(original: Array[float], mid: float, broad: float,
		strength: float) -> Array[float]:
	var weights: Array[float] = original.duplicate()
	var relief: Array[float] = [0.64, 0.48, 0.68, 0.22, 0.50,
		0.88, 0.84, 0.36, 0.96]
	var natural_total := 0.0
	var sculpted_total := 0.0
	for i in range(9):
		if i == 4:
			continue
		var weight: float = weights[i]
		natural_total += weight
		if weight > 0.001 and strength > 0.0:
			var local_detail: float = mid if i % 2 == 0 else 1.0 - mid
			var height: float = clampf(relief[i] +
				(local_detail - 0.5) * 0.24 +
				(broad - 0.5) * 0.12, 0.0, 1.0)
			var gain: float = maxf(0.25, 1.0 + (height - 0.5) * 1.55 *
				clampf(strength, 0.0, 1.0) * (1.0 - clampf(weight, 0.0, 1.0)))
			weights[i] *= gain
		sculpted_total += weights[i]
	if sculpted_total > 0.00001:
		var conserve: float = natural_total / sculpted_total
		for i in range(9):
			if i != 4:
				weights[i] *= conserve
	return weights


func run(t) -> void:
	t.current = "native graphics preset and GPU uniform wiring"
	var strengths: Array[float] = []
	for level in range(4):
		var val: float = float(GraphicsQuality.profile(level).get(
			"terrain_height_blend", -1.0))
		t.check(val >= 0.0 and val <= 1.0,
			"height-blend factor is bounded in every quality preset")
		strengths.append(val)
	t.eq(strengths[0], 0.0, "Performance does not incur extra terrain ALU")
	t.eq(strengths[1], 0.0, "Balanced retains its original ground transitions")
	t.check(strengths[2] > 0.35, "High blends rock and soil by relative relief")
	t.check(strengths[3] > strengths[2], "Ultra provides stronger layer definition")
	t.eq(GraphicsQuality.profile(-3)["terrain_height_blend"], strengths[0],
		"negative quality safely clamps")
	t.eq(GraphicsQuality.profile(100)["terrain_height_blend"], strengths[3],
		"quality above Ultra safely clamps")
	var setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_terrain_height_blend", {})
	t.eq(str(setting.get("type", "")), "float",
		"engine-level scalar is registered before terrain shader loads")
	t.near(float(setting.get("value", -1.0)), 0.0, 0.00001,
		"default world quality has zero additional shader workload")
	var controller: String = (GraphicsQuality as Script).source_code
	t.check(controller.contains(
		'global_shader_parameter_set(&"aa_terrain_height_blend"'),
		"quality switch updates all streamed chunks with one GPU global")
	t.check(not ChunkView.GROUND_SHADER.contains("aa_terrain_height_blend"),
		"painted Compatibility ground stays on its simpler material path")

	t.current = "shaded terrain preserves authored roads and site boundaries"
	var shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "full PBR ground shader loads")
	if shader == null:
		return
	var source: String = shader.code
	t.check(source.contains('terrain_height_blend.gdshaderinc'),
		"all 13 terrain materials can share one height-blend helper")
	t.check(source.contains(
		"aa_terrain_height_blend > 0.001 && detail_fade > 0.001"),
		"low tiers and far terrain skip height calculations")
	t.check(source.contains("road < 0.85"),
		"painted road boundaries are explicitly protected")
	t.check(source.contains("(w[9] + w[10] + w[11] + w[12]) < 0.40"),
		"authored urban and ruin paving preserve their old silhouette")
	t.check(source.contains("if (i == 4) {"),
		"natural terrain morphing skips road layer")
	t.check(source.contains("natural_sum / sculpted_sum"),
		"natural weight is conserved to preserve biome brightness")
	t.check(source.contains("w[i] = original * aa_terrain_relief_gain("),
		"one relief bias increases exposed stone and snow")
	t.check(source.find("aa_terrain_height_blend > 0.001") <
		source.find("int layer_budget = aa_terrain_layer_budget"),
		"height-aware ranking happens before top-2/3/4 GPU texture selection")
	t.check(source.contains("macro_color += layer_average[i] * weight;"),
		"small layers still contribute their palette averages")
	t.check(source.contains("SPECULAR = 0.5;") and
		source.contains("filter_specular_roughness(final_roughness, bent)"),
		"height layers retain physically based dielectric reflections")
	t.check(source.contains("aa_water_caustic_illumination("),
		"water caustics remain integrated with terrain shading")

	t.current = "texture-free height helper and realistic material priorities"
	var relief_source: String = FileAccess.get_file_as_string(
		"res://assets/shaders/terrain_height_blend.gdshaderinc")
	t.check(relief_source.contains("float relief[9] = {"),
		"rocks snow mud and sand use stable per-material height priorities")
	t.check(relief_source.contains("(layer % 2 == 0) ? mid : (1.0 - mid)"),
		"layers share already-computed noise with per-material phase variation")
	t.check(relief_source.contains("float blend_edge = 1.0 - clamp(weight"),
		"pure material pixels stay unchanged")
	t.check(not relief_source.contains("texture(") and
		not relief_source.contains("fbm(") and not relief_source.contains("value_noise("),
		"height blending adds no texture reads or additional noise octaves")
	t.check(not relief_source.contains("TIME") and
		not relief_source.contains("SCREEN_UV"),
		"height material boundaries do not shimmer with time or camera pan")

	t.current = "conservative 13-layer weight proof with protected road"
	var maps: Array[Array] = [
		[0.55, 0.0, 0.35, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 0.45, 0.0, 0.0, 0.0, 0.55, 0.0,
			0.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 0.0, 0.12, 0.45, 0.28, 0.0, 0.15,
			0.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
			0.65, 0.35, 0.0, 0.0],
	]
	for sample in maps:
		var original: Array[float] = []
		for v in sample:
			original.append(float(v))
		for amount in [0.0, 0.48, 0.85]:
			var result: Array[float] = _sculpt_natural(original, 0.65, 0.47,
				amount)
			t.near(result[4], original[4], 0.000001,
				"road coverage stays identical")
			var natural_before := 0.0
			var natural_after := 0.0
			for i in range(13):
				if i >= 9 or i == 4:
					t.near(result[i], original[i], 0.000001,
						"urban layer and protected road stay unchanged")
				else:
					natural_before += original[i]
					natural_after += result[i]
					t.check(result[i] >= 0.0,
						"height blending never creates negative terrain coverage")
					if original[i] == 0.0:
						t.eq(result[i], 0.0,
							"missing terrain materials do not bleed across biomes")
			t.near(natural_after, natural_before, 0.00001,
				"all natural layer coverage is conserved by height blending")
