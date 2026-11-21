extends RefCounted
## Texture-group-style sampler budgets for the existing 13-layer terrain PBR shader.
## Like desktop engine scalability settings, only the expensive terrain samplers
## use anisotropy at High/Ultra. Compatibility and Forward+ use the same
## shader language and exactly the same texture arrays / per-chunk uniforms.

const SOURCE_PATH := "res://assets/shaders/ground.gdshader"
const ALBEDO_LINEAR := "uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap, repeat_enable;"
const NORMAL_LINEAR := "uniform sampler2DArray normal_layers : hint_normal, filter_linear_mipmap, repeat_enable;"
const ALBEDO_ANISO := "uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;"
const NORMAL_ANISO := "uniform sampler2DArray normal_layers : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;"
const WET_COAT_DEFINE := "\n#define AA_TERRAIN_WET_CLEARCOAT"

# ShaderMaterial shader assignment can invalidate the material's parameter
# cache. Preserve actual biome, road, paving, texture-array and tint data when
# the player changes preset; do not re-upload or recompute any Image resources.
const PARAMETERS := [
	"albedo_layers", "normal_layers", "height_layers", "biome_map", "road_mask",
	"chunk_origin", "chunk_size", "biome_texels",
	"tile_meters", "normal_strength", "layer_tint",
	"layer_average", "site_patches",
]

static var _shaders: Dictionary = {}


## 0: standard trilinear, 1: anisotropic ground color, 2: color + normals.
## Normal filtering costs extra bandwidth, so it is exclusive to Ultra.
static func tier_for_quality(quality: int) -> int:
	if quality >= 3:
		return 2
	if quality >= 2:
		return 1
	return 0


## Pure shader-source change: preserve all texture names and uniform layout.
static func code_for_tier(source: String, tier: int) -> String:
	if tier <= 0 or not source.contains(ALBEDO_LINEAR):
		return source
	# High/Ultra use the cached anisotropic shader variants for a second
	# wet-film PBR lobe. Low tiers retain the original BRDF byte-for-byte.
	var code := source.replace(ALBEDO_LINEAR, ALBEDO_ANISO)
	code = code.replace("shader_type spatial;", "shader_type spatial;" + WET_COAT_DEFINE)
	if tier >= 2:
		code = code.replace(NORMAL_LINEAR, NORMAL_ANISO)
	return code


static func shader_for_quality(quality: int) -> Shader:
	var tier: int = tier_for_quality(quality)
	if _shaders.has(tier):
		return _shaders[tier]
	var original: Shader = load(SOURCE_PATH) as Shader
	if original == null:
		return null
	if tier == 0:
		_shaders[0] = original
		return original
	var code: String = code_for_tier(original.code, tier)
	if code == original.code:
		push_warning("Terrain anisotropic sampler anchors are missing; using the original PBR shader.")
		_shaders[tier] = original
		return original
	var variant := Shader.new()
	variant.code = code
	_shaders[tier] = variant
	return variant


## Called at preset changes only, never per frame or per terrain vertex.
static func apply(material: ShaderMaterial, quality: int) -> void:
	if material == null:
		return
	var target: Shader = shader_for_quality(quality)
	if target == null or material.shader == target:
		return
	var saved: Dictionary = {}
	for parameter in PARAMETERS:
		var value: Variant = material.get_shader_parameter(parameter)
		if value != null:
			saved[parameter] = value
	material.shader = target
	for parameter in saved:
		material.set_shader_parameter(parameter, saved[parameter])
