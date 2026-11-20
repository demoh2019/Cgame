extends RefCounted
## PBR micro-occlusion reuses the terrain's normal maps and the existing AO
## channel. This feature must never add an extra screen pass or GPU texture.
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "terrain micro-occlusion quality budget"
	var definition: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_terrain_micro_occlusion", {})
	t.eq(str(definition.get("type", "")), "float",
		"one shared float controls terrain micro-shadows")
	t.near(float(definition.get("value", -1.0)), 0.0, 0.0001,
		"early scene loading keeps new shading disabled until quality is applied")
	var previous := -1.0
	for tier in 4:
		var value: float = float(Quality.profile(tier).get("micro_occlusion", -1.0))
		t.check(value >= 0.0 and value <= 1.0,
			"micro-shadow budget is bounded")
		t.check(value >= previous, "higher visual tiers never reduce micro-shadows")
		previous = value
	t.eq(Quality.profile(0)["micro_occlusion"], 0.0,
		"Performance preserves its zero-cost terrain path")
	t.eq(Quality.profile(1)["micro_occlusion"], 0.0,
		"Balanced preserves its zero-cost terrain path")
	t.check(float(Quality.profile(2)["micro_occlusion"]) > 0.0,
		"High adds grounded relief shadows")
	t.check(float(Quality.profile(3)["micro_occlusion"]) >
		float(Quality.profile(2)["micro_occlusion"]),
		"Ultra gets slightly stronger small-scale contact depth")

	t.current = "micro-shadow shader integrates with existing PBR lighting"
	var shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "the existing ground shader loads")
	if shader == null:
		return
	var source: String = shader.code
	t.check(source.contains("global uniform float aa_terrain_micro_occlusion;"),
		"quality reaches streamed chunks through one shared uniform")
	t.check(source.contains("micro_cavity = 1.0 - clamp(bump.z, 0.0, 1.0)"),
		"ambient shadowing derives from the already sampled PBR normals")
	t.check(source.contains("micro_cavity * 0.32 * aa_terrain_micro_occlusion * detail_fade"),
		"near-field detail and quality gate the additional shader arithmetic")
	t.check(source.contains("(1.0 - puddle * 0.85)"),
		"wet puddles soften micro-crevice shadows")
	t.check(source.contains("AO = clamp(ground_contact * micro_shadow * cavity_visibility"),
		"micro-shadows and curvature combine into bounded PBR AO, not a new pass")
	t.check(source.contains("float cavity_visibility = 1.0 - cavity * 0.24 * (1.0 - puddle * 0.85);"),
		"rain-filled cavities gradually restore indirect PBR reflection visibility")
	t.check(source.contains("min(0.18,"),
		"the micro-shadow contribution remains subtle even on Ultra")
	t.check(source.contains("ROUGHNESS = filter_specular_roughness"),
		"existing roughness and specular anti-aliasing are preserved")
	var control_source: String = (Quality as Script).source_code
	t.check(control_source.contains(
		'global_shader_parameter_set(&"aa_terrain_micro_occlusion"'),
		"the live graphics controller updates all streamed terrain materials")
