extends RefCounted
## Real triplanar cliffs and physically variable terrain roughness; GPU-less regression.
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "rock detail quality levels and global renderer configuration"
	var config: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_cliff_normal_quality", {})
	t.eq(str(config.get("type", "")), "float", "cliff setting registered as a float")
	t.near(float(config.get("value", -1.0)), 0.0, 0.0001,
		"default skips expensive samples until graphics preset is applied")
	var stages := []
	for level in range(4):
		var strength: float = float(GraphicsQuality.profile(level).get(
			"cliff_normal_quality", -1.0))
		t.check(strength >= 0.0 and strength <= 1.0,
			"GPU rock relief remains in a bounded range")
		stages.append(strength)
	t.eq(stages[0], 0.0, "Performance skips rock normal projections")
	t.eq(stages[1], 0.0, "Balanced skips rock normal projections")
	t.check(float(stages[2]) > 0.5, "High improves nearby cliff normals")
	t.eq(stages[3], 1.0, "Ultra full-strength cliff normals")
	t.eq(GraphicsQuality.profile(-5)["cliff_normal_quality"], stages[0],
		"invalid lower tier clamps")
	t.eq(GraphicsQuality.profile(90)["cliff_normal_quality"], stages[3],
		"invalid upper tier clamps")

	t.current = "physically layered wet dielectric finish"
	var coat: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_terrain_wet_clearcoat", {})
	t.eq(str(coat.get("type", "")), "float",
		"wet-film BRDF uses a single shared scalar")
	t.near(float(coat.get("value", -1.0)), 0.0, 0.0001,
		"base quality has no extra clearcoat lighting")
	t.check(float(GraphicsQuality.profile(3)["wet_clearcoat"]) >
		float(GraphicsQuality.profile(2)["wet_clearcoat"]),
		"Ultra has a stronger premium rain film than High")
	t.current = "GPU shader computes rock normals with distance and blend weights"
	var shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "existing PBR terrain shader loads")
	if shader == null:
		return
	var code: String = shader.code
	t.check(code.contains("global uniform float aa_cliff_normal_quality"),
		"GPU global controls detail cost")
	t.check(code.contains(
		"aa_cliff_normal_quality > 0.001 && detail_fade > 0.001"),
		"no cliff normal taps in low tiers or outside camera detail radius")
	t.check(code.contains("textureGrad(normal_layers") and
		code.contains("cliff_dx_zy, cliff_dy_zy") and
		code.contains("cliff_dx_xy, cliff_dy_xy"),
		"all three cliff normals have explicit mip derivatives")
	t.check(code.contains(
		"along_x * blend.x + along_y * blend.y + along_z * blend.z"),
		"projection normals are combined in world space")
	t.check(code.contains("cliff_mix = clamp(w[5] / max(all_weight"),
		"relief is weighted by real cliff material not pasted over plants")
	t.check(code.contains("bent = normalize(mix(bent, cliff_world_normal, cliff_mix));"),
		"cliffs blend back to original terrain normals")
	t.check(code.contains("w[5] * 0.73") and code.contains("w[9] * 0.72")
		and code.contains("w[7] * 0.93"),
		"rock asphalt and sand have distinct physical roughness")
	t.check(code.contains("SPECULAR = 0.5;"),
		"rain changes surface roughness instead of unrealistic dielectric F0")
	t.check(code.contains("wetness * 0.55") and code.contains("puddle * 0.9"),
		"old wet ground/puddles remain in shader")
	t.check(code.contains("layer_average[i]") and code.contains("site_patches"),
		"macro color and roads preserved")
	var quality_code: String = (GraphicsQuality as Script).source_code
	t.check(quality_code.contains(
		'global_shader_parameter_set(&"aa_cliff_normal_quality"'),
		"graphics preset changes update single shared uniform")
