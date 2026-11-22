extends RefCounted
## Terrain texture filtering follows the graphics preset while retaining all
## streamed biome/road maps and the original 13-layer PBR shader.
const Anisotropy = preload("res://scripts/client/terrain_anisotropy.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "texture group budgets"
	t.eq(Anisotropy.tier_for_quality(-3), 0, "invalid low level retains cheap trilinear")
	t.eq(Anisotropy.tier_for_quality(0), 0, "Performance keeps trilinear albedo and normals")
	t.eq(Anisotropy.tier_for_quality(1), 0, "Balanced keeps trilinear albedo and normals")
	t.eq(Anisotropy.tier_for_quality(2), 1, "High sharpens color without normal-map bandwidth")
	t.eq(Anisotropy.tier_for_quality(3), 2, "Ultra sharpens both albedo and normal maps")
	t.eq(Anisotropy.tier_for_quality(99), 2, "unknown high preset remains bounded")

	t.current = "preserve all shading while changing sampler selection"
	var baseline: Shader = load(Anisotropy.SOURCE_PATH) as Shader
	t.check(baseline != null, "real textured terrain shader exists")
	if baseline == null:
		return
	var base_code: String = baseline.code
	var high_code: String = Anisotropy.code_for_tier(base_code, 1)
	var ultra_code: String = Anisotropy.code_for_tier(base_code, 2)
	t.eq(Anisotropy.code_for_tier(base_code, 0), base_code, "low tier is byte-for-byte original")
	t.check(high_code.contains(Anisotropy.ALBEDO_ANISO), "High uses anisotropic albedo sampling")
	t.check(high_code.contains(Anisotropy.NORMAL_LINEAR), "High retains cheap normal filtering")
	t.check(ultra_code.contains(Anisotropy.ALBEDO_ANISO), "Ultra keeps sharp albedo")
	t.check(ultra_code.contains(Anisotropy.NORMAL_ANISO), "Ultra improves grazing-angle normals")
	t.check(high_code.contains("aa_terrain_layer_budget")
		and high_code.contains("site_patches") and high_code.contains("textureGrad("),
		"existing texture budgets, roads and mip gradients are unchanged")
	t.check(ultra_code.contains("aa_weather_wetness")
		and ultra_code.contains("aa_cliff_normal_quality"),
		"weather and cliff PBR are preserved")
	t.eq(high_code.length(), base_code.length() +
		Anisotropy.ALBEDO_ANISO.length() - Anisotropy.ALBEDO_LINEAR.length() +
		Anisotropy.WET_COAT_DEFINE.length(),
		"High changes one sampler and enables a wet-film PBR variant")
	t.eq(ultra_code.length(), high_code.length() +
		Anisotropy.NORMAL_ANISO.length() - Anisotropy.NORMAL_LINEAR.length(),
		"Ultra changes one additional sampler declaration")

	t.current = "shader variant excludes expensive clearcoat on lower tiers"
	t.check(not base_code.contains("#define AA_TERRAIN_WET_CLEARCOAT"),
		"base source has no active clearcoat macro")
	t.check(high_code.contains("#define AA_TERRAIN_WET_CLEARCOAT")
		and ultra_code.contains("#define AA_TERRAIN_WET_CLEARCOAT"),
		"only High/Ultra compile the second dielectric specular lobe")
	t.check(base_code.contains("#ifdef AA_TERRAIN_WET_CLEARCOAT")
		and base_code.contains("CLEARCOAT = clamp(water_film"),
		"cached premium variants shade existing wet paving as thin film")
	t.check(base_code.contains("r_hard_surface = clamp(w[4]") and
		base_code.contains("w[9] + w[10] + w[11]"),
		"coating follows roads, asphalt, stone and masonry")
	t.check(base_code.contains("water_film = wetness * hard_surface * detail_fade")
		and base_code.contains("clamp(w[8], 0.0, 1.0)"),
		"coating fades with distance, weather and excludes snow")
	t.check(not base_code.contains("clearcoat_texture"),
		"no new coat texture, VRAM, or screen pass is required")
	t.check(base_code.contains("water_film *= 0.86 + cavity * 0.14")
		and base_code.contains("* (1.0 - clamp(w[8], 0.0, 1.0)) * (1.0 - ruin_moss * 0.45)"),
		"wet reflections collect in worn recesses and preserve porous moss")
	t.check(base_code.contains("water_film *= 1.0 - smoothstep(0.20, 0.70, slope)"),
		"sloped surfaces cannot reflect as much as waterlogged roads")
	t.check(base_code.contains("CLEARCOAT_ROUGHNESS = filter_specular_roughness"),
		"water-film specular highlights reuse the engine's roughness antialiasing")

	t.current = "cached shader variants and live material state"
	var plain: Shader = Anisotropy.shader_for_quality(0)
	var high: Shader = Anisotropy.shader_for_quality(2)
	var ultra: Shader = Anisotropy.shader_for_quality(3)
	t.check(plain == baseline, "low tier uses original compiled shader resource")
	t.check(high != null and high != plain, "High owns one cached shader variant")
	t.check(ultra != null and ultra != high, "Ultra owns one cached shader variant")
	t.check(Anisotropy.shader_for_quality(2) == high, "high shader is never regenerated per chunk")
	t.check(Anisotropy.shader_for_quality(3) == ultra, "ultra shader is never regenerated per chunk")
	var material := ShaderMaterial.new()
	material.shader = plain
	var origin := Vector2(64.0, -128.0)
	var paving := PackedVector4Array([
		Vector4(12.0, 34.0, 50.0, 11.0),
		Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
	var tint := PackedVector3Array()
	var averages := PackedVector3Array()
	for index in 13:
		tint.append(Vector3.ONE)
		averages.append(Vector3(0.2, 0.3, 0.4))
	material.set_shader_parameter("chunk_origin", origin)
	material.set_shader_parameter("site_patches", paving)
	material.set_shader_parameter("layer_tint", tint)
	material.set_shader_parameter("layer_average", averages)
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.4, 0.6, 0.8))
	var biome: ImageTexture = ImageTexture.create_from_image(image)
	material.set_shader_parameter("biome_map", biome)
	Anisotropy.apply(material, 2)
	t.check(material.shader == high, "High is activated on existing chunks")
	t.eq(material.get_shader_parameter("chunk_origin"), origin,
		"world-space texture positions do not move after quality switch")
	t.eq(material.get_shader_parameter("site_patches"), paving,
		"paving layouts do not disappear")
	t.eq(material.get_shader_parameter("layer_tint"), tint,
		"Poly Haven color calibration is retained")
	t.eq(material.get_shader_parameter("layer_average"), averages,
		"unsampled biome colors are retained")
	t.check(material.get_shader_parameter("biome_map") == biome,
		"per-chunk biome texture is not reallocated")
	Anisotropy.apply(material, 3)
	t.check(material.shader == ultra, "Ultra is activated")
	t.eq(material.get_shader_parameter("chunk_origin"), origin,
		"second tier change keeps world-space mapping")
	Anisotropy.apply(material, 1)
	t.check(material.shader == plain, "switch back to low tier restores original shader")
	t.check(material.get_shader_parameter("biome_map") == biome,
		"texture remains intact after returning to Balanced")
	Anisotropy.apply(material, 1)
	t.check(material.shader == plain, "no work on an unchanged tier")

	t.current = "preset and GPU parameter integration"
	t.check(ProjectSettings.has_setting("shader_globals/aa_terrain_wet_clearcoat"),
		"wet film strength is registered before the world is streamed")
	var strengths := []
	for level in range(4):
		var film: float = float(GraphicsQuality.profile(level).get("wet_clearcoat", -1.0))
		t.check(film >= 0.0 and film <= 0.65, "terrain wet-film intensity stays bounded")
		strengths.append(film)
	t.eq(strengths[0], 0.0, "Performance skips film")
	t.eq(strengths[1], 0.0, "Balanced skips film")
	t.check(strengths[2] > 0.0 and strengths[3] > strengths[2],
		"higher visual quality increases wet hard-surface reflection detail")
	t.check((GraphicsQuality as Script).source_code.contains(
		'global_shader_parameter_set(&"aa_terrain_wet_clearcoat"'),
		"live graphics controller updates the PBR coat on existing chunks")
	t.current = "game integration"
	var graphics_code: String = (GraphicsQuality as Script).source_code
	var chunk_code: String = (ChunkView as Script).source_code
	t.check(graphics_code.contains("ChunkView.configure_terrain_filter(_level)"),
		"quality controller applies sampler budget")
	t.check(graphics_code.contains("ChunkView.apply_terrain_filter(terrain)"),
		"loaded terrain chunks change immediately")
	t.check(chunk_code.contains("_terrain.add_to_group(TERRAIN_GROUP)"),
		"new textured terrain registers for quality changes")
	t.check(chunk_code.contains("TerrainAnisotropy.shader_for_quality(terrain_filter_quality)"),
		"future streamed chunks use current sampler quality")
