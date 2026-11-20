extends RefCounted
## Weather-responsive outfit materials without a new shader, draw pass, or
## duplicated PBR textures. All animated characters share the same per-source
## material variants. Godot's StandardMaterial3D preserves source maps/tangents.
## Only real imported opaque clothing/gear is registered by CharacterModel.

const STEPS := 4
const QUALITY_STRENGTH := [0.0, 0.35, 0.72, 1.0]
static var _variants: Dictionary = {} # Source resource ID -> {wetness step: shared material}


static func supports(source: StandardMaterial3D) -> bool:
	return source != null and source.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
		and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED


## Only apply expensive clearcoat in the Forward+ High/Ultra renderers.
## Compatibility still darkens fabric slightly on wet days at one cheap tier.
static func step_for(wetness: float, quality: int, method: String) -> int:
	if not is_finite(wetness) or wetness <= 0.0:
		return 0
	var tier: int = clampi(quality, 0, QUALITY_STRENGTH.size() - 1)
	var fraction: float = clampf(wetness, 0.0, 1.0) * float(QUALITY_STRENGTH[tier])
	var step: int = clampi(roundi(fraction * float(STEPS)), 0, STEPS)
	if method != "forward_plus":
		step = mini(step, 1)
	return step


static func variant(source: StandardMaterial3D, step: int) -> StandardMaterial3D:
	if not supports(source):
		return source
	var tier: int = clampi(step, 0, STEPS)
	if tier <= 0:
		return source
	var id: int = source.get_instance_id()
	var cached: Dictionary = _variants.get(id, {})
	if cached.has(tier):
		return cached[tier]
	# Duplicate only lightweight material state, keeping albedo, normal,
	# ORM, roughness and metallic texture resources shared and unmodified.
	var wet: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	var strength: float = float(tier) / float(STEPS)
	wet.roughness = clampf(lerpf(source.roughness,
		maxf(0.28, source.roughness * 0.68), strength), 0.1, 1.0)
	var base: Color = source.albedo_color
	wet.albedo_color = Color(base.r * (1.0 - 0.10 * strength),
		base.g * (1.0 - 0.10 * strength), base.b * (1.0 - 0.10 * strength), base.a)
	if tier >= 2:
		# Unreal-style layered clear-coat BRDF: tiny water film over
		# the original fabric/metal PBR. Does not affect transparent hair.
		wet.clearcoat_enabled = true
		wet.clearcoat = maxf(wet.clearcoat if source.clearcoat_enabled else 0.0,
			0.24 * strength)
		wet.clearcoat_roughness = minf(source.clearcoat_roughness, 0.18)
	cached[tier] = wet
	_variants[id] = cached
	return wet


static func clear_cache() -> void:
	_variants.clear()
