extends RefCounted
## Terrain material complexity must scale with distance while remaining compatible with the game's renderer.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const GroundContactAO = preload("res://scripts/client/ground_contact_ao.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


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

	t.current = "ruin moss reuses existing shading"
	if ground != null:
		var code: String = ground.code
		t.check(code.contains("float ruin_share = clamp((w[9] + w[10] + w[11] + w[12])"),
			"ruin moss is limited to paved urban materials, not forests or sandy beaches")
		t.check(code.contains("smoothstep(0.34, 0.72, mid)"),
			"ruin moss uses existing mid-frequency detail without another noise evaluation")
		t.check(code.contains("color *= mix(vec3(1.0), vec3(0.75, 0.92, 0.73), ruin_moss)"),
			"aging shifts the albedo gently without extra texture samples")
		t.check(code.contains("r_dry_roughness = mix(r_dry_roughness, 0.92, ruin_moss * 0.45)"),
			"moss makes urban ground more matte, without removing rain puddle highlights")
		t.check(code.contains("puddle * 0.9"), "existing puddle response remains after moss shading")
	for paved_share in [0.0, 0.3, 0.6, 1.0]:
		var old_mid := 0.6
		var moss: float = paved_share * smoothstep(0.34, 0.72, old_mid) * 0.5
		t.check(moss >= 0.0 and moss <= 0.5,
			"urban moss tint is bounded and vanishes on unpaved ground")

	t.current = "vertex-interpolated macro terrain shading"
	if ground != null:
		var source: String = ground.code
		var vertex_start: int = source.find("void vertex()")
		var fragment_start: int = source.find("void fragment()")
		t.check(vertex_start >= 0 and fragment_start > vertex_start, "terrain shader has a vertex-to-fragment pipeline")
		var vertex_code: String = source.substr(vertex_start, fragment_start - vertex_start)
		var fragment_code: String = source.substr(fragment_start)
		t.check(vertex_code.contains("aa_macro_broad = fbm(world_position.xz * 0.012);"),
			"macro biome noise moves to the vertex stage")
		t.check(not fragment_code.contains("fbm(p * 0.012)"),
			"large terrain pixel count no longer repeats macro-noise octaves")
		t.check(fragment_code.contains("float broad = aa_macro_broad;"),
			"all existing biome, snow and weather weights share interpolated macro noise")
		t.check(vertex_code.contains("aa_vertex_cloud_shadow = cloud_shadow(world_position.xz, TIME);"),
			"large cloud shadows sample the same LUT in the vertex stage")
		t.check(not fragment_code.contains("apply_cloud_shadow(color, p, TIME)"),
			"landscape fragments skip the redundant cloud texture lookup")
		t.check(fragment_code.contains("aa_vertex_cloud_shadow"),
			"cloud color grading uses interpolated shadow strength")
		t.check(fragment_code.contains("float mid = aa_vertex_mid;") and
			fragment_code.contains("mid = mix(aa_vertex_mid, fbm(p * 0.07 + 3.0), detail_fade);"),
			"near soil detail remains pixel-accurate and distant terrain interpolates vertices")
		t.check(fragment_code.find("float mid = aa_vertex_mid;") <
			fragment_code.find("vec2 warp = vec2(mid - 0.44,"),
			"domain warp never reads an uninitialized mid-frequency field")
		t.check(fragment_code.contains("textureGrad(normal_layers"),
			"high-frequency normal detail remains supported")

	t.current = "triplanar rock color LOD: full near-detail, zero far texture fetches"
	if ground != null:
		var code: String = ground.code
		var cliff_start: int = code.find("if (i == 5) {")
		var cliff_end: int = code.find("} else {", cliff_start)
		t.check(cliff_start >= 0 and cliff_end > cliff_start,
			"the imported rock branch remains isolated from the other twelve materials")
		var cliff_code: String = code.substr(cliff_start, cliff_end - cliff_start)
		t.check(cliff_code.contains("c = layer_average[5];"),
			"far rock uses the exact palette average already bound by ChunkView")
		t.check(cliff_code.contains("if (detail_fade > 0.001)"),
			"three expensive cliff albedo fetches are gated by camera distance")
		t.check(cliff_code.contains("c = mix(c, cliff_detail * layer_tint[5], detail_fade);"),
			"full triplanar color fades in smoothly without geometric seams")
		t.check(cliff_code.contains("aa_cliff_normal_quality > 0.001"),
			"three cliff normal samples remain exclusive to High and Ultra")
		t.check(cliff_code.contains("textureGrad(albedo_layers, vec3(world_position.zy"),
			"X projection preserves imported rock and correct mip gradients")
		t.check(cliff_code.contains("textureGrad(albedo_layers, vec3(world_position.xy"),
			"Z projection remains available at close camera range")
		t.check(cliff_code.contains("vec3 blend = pow(abs(n), vec3(4.0));"),
			"near mapping still blends by true slope rather than a hard projection axis")
		t.check(cliff_code.contains("c = mix(c, cliff_detail * layer_tint[5], detail_fade);"),
			"rock PBR hue still uses the game's original terrain palette")
		t.check(cliff_code.contains("if (aa_cliff_normal_quality > 0.001) {"),
			"normal-map sampling is nested inside the distance gate")
		t.check(code.contains("float detail_fade = 1.0 - smoothstep(aa_terrain_detail_radius"),
			"the quality preset still controls the distance of full-detail cliffs")
		t.check(code.contains("vec3 cliff_world_normal = n;"),
			"distant rock returns to geometry normal without extra texture lookups")

	# The interpolation cannot change either endpoint or any material weights.
	for fraction in [0.0, 0.1, 0.35, 0.5, 0.85, 1.0]:
		var result: Color = Color(0.42, 0.39, 0.36).lerp(
			Color(0.50, 0.47, 0.42), fraction)
		t.check(result.r >= 0.42 and result.r <= 0.50,
			"transition keeps rock albedo in the original material color range")
		t.check(result.g >= 0.39 and result.g <= 0.47,
			"triplanar rock blends without an overshooting color band")

	t.current = "baked terrain ground contact"
	t.check(ProjectSettings.has_setting("shader_globals/aa_ground_contact_strength"), "one common shader global controls contact AO")
	var low_contact: float = float(GraphicsQuality.profile(0)["ground_contact_strength"])
	var high_contact: float = float(GraphicsQuality.profile(3)["ground_contact_strength"])
	t.eq(low_contact, 0.0, "Performance skips the contact-mask texture read")
	t.check(high_contact > float(GraphicsQuality.profile(1)["ground_contact_strength"]), "higher presets preserve nearby ground contact")
	var empty: PackedByteArray = GroundContactAO.mask_bytes(Vector2.ZERO, 64.0, [], [])
	t.eq(empty.size(), GroundContactAO.SIZE * GroundContactAO.SIZE, "mask fits a single 64px L8 surface")
	t.eq(empty[32 * GroundContactAO.SIZE + 32], 255, "no objects means no dark contact spots")
	var tree_node := {"kind": "tree", "id": 712, "x": 32.0, "z": 32.0}
	var tree_nodes: Array = [tree_node]
	var stamped: PackedByteArray = GroundContactAO.mask_bytes(Vector2.ZERO, 64.0, tree_nodes, [])
	t.check(stamped[31 * GroundContactAO.SIZE + 31] < 255, "tree trunk creates a local soft dark contact")
	t.eq(stamped[0], 255, "contact stamp does not shade unrelated terrain")
	var depleted: PackedByteArray = GroundContactAO.mask_bytes(Vector2.ZERO, 64.0, tree_nodes, [], {712: true})
	t.eq(depleted[31 * GroundContactAO.SIZE + 31], 255, "depleted tree no longer leaves a static contact stain")
	var border_tree: Array = [{"kind": "tree", "x": 0.5, "z": 32.0}]
	var border_mask: PackedByteArray = GroundContactAO.mask_bytes(Vector2.ZERO, 64.0, border_tree, [])
	t.check(border_mask[32 * GroundContactAO.SIZE] > stamped[31 * GroundContactAO.SIZE + 31],
		"imprints fade at chunk borders to avoid visible seams")
	var terrain_shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(terrain_shader != null and terrain_shader.code.contains("uniform sampler2D contact_map"),
		"textured landscape receives baked ground contact map")
	t.check(terrain_shader != null and terrain_shader.code.contains("AO = ground_contact;"),
		"landscape PBR ambient light respects local contacts")
	t.check(ChunkView.GROUND_SHADER.contains("uniform sampler2D contact_map"),
		"fallback procedural landscape uses the same contact shading")
	t.check(ChunkView.GROUND_SHADER.contains("AO = ground_contact;"),
		"Compatibility fallback receives the contact occlusion")
	var quality_controller := load("res://scripts/client/graphics_quality.gd") as GDScript
	t.check(quality_controller != null and quality_controller.source_code.contains('global_shader_parameter_set(&"aa_ground_contact_strength"'),
		"graphics quality updates one contact shadow budget for all chunks")
