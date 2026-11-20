extends RefCounted
## GPU-independent regressions for world-space PBR terrain anti-tiling.
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "terrain variation quality levels"
	var registered: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_terrain_warp_strength", {})
	t.eq(str(registered.get("type", "")), "float", "shared uniform is a float")
	t.near(float(registered.get("value", -1.0)), 0.0, 0.00001,
		"the initial default avoids extra work on low-end hardware")
	var low: Dictionary = GraphicsQuality.profile(0)
	var balanced: Dictionary = GraphicsQuality.profile(1)
	var high: Dictionary = GraphicsQuality.profile(2)
	var ultra: Dictionary = GraphicsQuality.profile(3)
	t.near(float(low["terrain_warp_strength"]), 0.0, 0.00001,
		"Performance shader skips distortion")
	t.near(float(balanced["terrain_warp_strength"]), 0.0, 0.00001,
		"Balanced remains cheap")
	t.check(float(high["terrain_warp_strength"]) > 0.0 and
		float(high["terrain_warp_strength"]) < float(ultra["terrain_warp_strength"]),
		"High gently varies textures, Ultra increases breakup")
	t.check(float(ultra["terrain_warp_strength"]) <= 0.55,
		"warping cannot stretch physically based tiles excessively")
	t.eq(GraphicsQuality.profile(-12), low, "invalid low preset is safe")
	t.eq(GraphicsQuality.profile(99), ultra, "invalid high preset is safe")

	t.current = "continuous world-space material sampling"
	var shader: Shader = load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "the real PBR terrain shader loads")
	if shader == null:
		return
	var src: String = shader.code
	t.check(src.contains("global uniform float aa_terrain_warp_strength;"),
		"shader declares the same globally registered parameter")
	t.check(src.contains("if (aa_terrain_warp_strength > 0.001)"),
		"cheap presets bypass per-pixel domain warp")
	t.check(src.contains("vec2 warp = vec2(mid - 0.44,"),
		"reuse existing noise fields rather than adding texture reads")
	t.check(src.contains("material_p += warp;"), "material UVs are varied in world space")
	t.check(src.contains("lod_dx += dFdx(warp / tile_meters);") and
		src.contains("lod_dy += dFdy(warp / tile_meters);"),
		"mip gradients account for texture deformation")
	t.check(src.contains("top_albedo(layer, material_p,") and
		src.contains("top_normal(layer, material_p,"),
		"albedo and PBR normal textures remain registered")
	t.check(src.contains("vec2 local = (p - chunk_origin) / chunk_size;"),
		"the biome map stays in authoritative world coordinates")
	t.check(src.contains("vec2 offset = p - patch.xy;"),
		"ruin paving and site masks do not shift")
	t.check(src.contains("textureLod(road_mask, local, 0.0)"),
		"roads follow the old map instead of distorted material UVs")
	t.check(src.contains("textureGrad(albedo_layers") and
		src.contains("textureGrad(normal_layers"),
		"existing texture arrays and trilinear/aniso sample paths remain")
	var quality_code: String = (GraphicsQuality as Script).source_code
	t.check(quality_code.contains(
		'global_shader_parameter_set(&"aa_terrain_warp_strength"'),
		"quality changes publish one uniform for every streamed chunk")
