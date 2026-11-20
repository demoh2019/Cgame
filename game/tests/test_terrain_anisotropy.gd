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
		Anisotropy.ALBEDO_ANISO.length() - Anisotropy.ALBEDO_LINEAR.length(),
		"High changes only one sampler declaration")
	t.eq(ultra_code.length(), high_code.length() +
		Anisotropy.NORMAL_ANISO.length() - Anisotropy.NORMAL_LINEAR.length(),
		"Ultra changes one additional sampler declaration")

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
