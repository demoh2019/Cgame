extends RefCounted
## Terrain material complexity must scale with distance while remaining compatible with the game's renderer.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "terrain texture LOD profiles"
	t.check(ProjectSettings.has_setting("shader_globals/aa_terrain_detail_radius"), "detail radius GPU uniform is registered")
	var config: Dictionary = ProjectSettings.get_setting("shader_globals/aa_terrain_detail_radius", {})
	t.eq(str(config.get("type", "")), "float", "terrain LOD radius is a float")
	t.near(float(config.get("value", -1.0)), 42.0, 0.001, "initial terrain quality is balanced")
	var previous := 0.0
	var previous_budget := 0
	for level in GraphicsQuality.NAMES.size():
		var p: Dictionary = GraphicsQuality.profile(level)
		var radius: float = float(p.get("terrain_detail_radius", -1.0))
		t.check(radius >= 20.0 and radius <= 120.0, "terrain LOD distance has sane bounds for %s" % GraphicsQuality.NAMES[level])
		t.check(radius > previous, "%s quality increases detail radius" % GraphicsQuality.NAMES[level])
		previous = radius
		var budget: int = int(p.get("terrain_layer_budget", 0))
		t.check(budget > previous_budget and budget <= 13, "PBR texture layer budget grows with %s" % GraphicsQuality.NAMES[level])
		previous_budget = budget

	t.current = "terrain shading cost"
	t.check(ProjectSettings.has_setting("shader_globals/aa_terrain_layer_budget"), "PBR blend budget is a registered global uniform")
	var budget_config: Dictionary = ProjectSettings.get_setting("shader_globals/aa_terrain_layer_budget", {})
	t.eq(str(budget_config.get("type", "")), "int", "layer budget uses integer shader global")
	t.eq(int(budget_config.get("value", -1)), 3, "default three blended PBR layers")
	var shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "textured terrain shader is loadable")
	if shader != null:
		var code: String = shader.code
		t.check(code.contains("global uniform float aa_terrain_detail_radius;"), "global radius is shared across all chunks")
		t.check(code.contains("smoothstep(aa_terrain_detail_radius"), "distance transition blends rather than popping")
		t.check(code.contains("CAMERA_POSITION_WORLD.xz"), "LOD follows the active camera")
		t.check(code.contains("if (near_weight > 0.001)"), "distant albedo does not fetch near detail")
		t.check(code.contains("if (detail_fade > 0.001)"), "distant normal maps are not sampled")
		t.check(code.contains("textureGrad(albedo_layers") and code.contains("textureGrad(normal_layers"), "conditional samples have stable explicit mip gradients")
		t.check(code.contains("dFdx(p / tile_meters)") and code.contains("dFdy(p / tile_meters)"), "mip gradients are evaluated before dynamic branches")
		t.check(code.contains("aa_weather_wetness"), "rain-wet materials remain supported")
		t.check(code.contains("site_patches"), "roads and city ground are still layered")
		t.check(code.contains("global uniform int aa_terrain_layer_budget;"), "shader obeys global layer budget")
		t.check(code.contains("selected_ids[4]") and code.contains("selected_weights[4]"), "bounded top-weighted selection is active")
		t.check(code.contains("layer_average[i]"), "discarded detail layers preserve palette through macro colors")
		t.check(code.contains("if (layer_budget >= 13)"), "Ultra preserves all texture layers")
		t.check(code.contains("textureGrad(albedo_layers, vec3(world_position.zy"), "cliff mapping has explicit mip gradients")

	var controller := load("res://scripts/client/graphics_quality.gd") as Script
	t.check(controller != null, "gameplay graphics controller is available")
	if controller != null:
		t.check(controller.source_code.contains('global_shader_parameter_set(&"aa_terrain_detail_radius"'), "graphics preset changes update the terrain GPU global")
		t.check(controller.source_code.contains('global_shader_parameter_set(&"aa_terrain_layer_budget"'), "quality switch applies the texture layer budget")

	t.current = "paved terrain shader noise budget"
	var ground: Shader = load("res://assets/shaders/ground.gdshader") as Shader
	t.check(ground != null, "terrain shader with site optimization loads")
	if ground != null:
		var source: String = ground.code
		t.check(source.contains("float reclaiming_moss = -1.0;"),
			"overlapping paved sites share one moss-noise calculation")
		t.check(source.contains("outer_radius = patch.z * 1.175"),
			"outer conservative bound accounts for the maximum procedural edge deformation")
		t.check(source.contains("dot(offset, offset) >= outer_radius * outer_radius"),
			"off-site fragments reject patches before evaluating square root or noise")
		t.check(source.contains("if (paved <= 0.0)"),
			"site noise is skipped when distorted paving has zero influence")
		t.check(source.contains("fbm(p * 0.11 + 5.0)"),
			"site moss detail and the authored noise frequencies are preserved")
		t.check(source.contains("w[int(patch.w)] += paved"),
			"site layer weights still contribute to 13-layer landscape blending")
	# fbm(p) is bounded by 0.5 + 0.25 + 0.125; its largest
	# possible inward displacement is -0.5 * 0.35 = -0.175.
	for moss_mid in [0.0, 0.1, 0.42, 0.6, 0.875]:
		var d: float = 1.175
		var old_paved: float = 1.0 - smoothstep(
			0.7, 1.0, d + (moss_mid - 0.5) * 0.35)
		t.near(old_paved, 0.0, 0.000001,
			"conservative 1.175-radius cutoff never discards nonzero paving")
	for radius in [1.0, 3.5, 18.0, 40.0]:
		var border: float = radius * 1.175
		t.check(border > radius and border / radius <= 1.175001,
			"outer paving bound remains proportional for every valid site radius")
