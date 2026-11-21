extends RefCounted
## Area-light softness for local lights (UE5 Source Radius, HDRP area/PCSS).
## Torches, lanterns and campfires get a physical emitter size so their
## shadows soften with distance; Godot's PCSS filter quality follows the tier.

const GROUP := &"aa_area_light"
const META_RADIUS := &"aa_area_radius"

static var _level: int = 1


static func filter_quality(level: int) -> int:
	match clampi(level, 0, 3):
		0:
			return RenderingServer.SHADOW_QUALITY_HARD
		1:
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		2:
			return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		_:
			return RenderingServer.SHADOW_QUALITY_SOFT_HIGH


## Emitter radius actually used: PCSS is skipped below High (it costs blocker search taps).
static func size_for(level: int, emitter_radius: float) -> float:
	return maxf(0.0, emitter_radius) if clampi(level, 0, 3) >= 2 else 0.0


static func register(light: Light3D, emitter_radius: float) -> void:
	if light == null:
		return
	light.set_meta(META_RADIUS, emitter_radius)
	if not light.is_in_group(GROUP):
		light.add_to_group(GROUP)
	_apply_one(light)


static func configure(level: int, tree: SceneTree) -> void:
	_level = clampi(level, 0, 3)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter_quality(_level))
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		_apply_one(node as Light3D)


static func _apply_one(light: Light3D) -> void:
	if light == null or not (light is OmniLight3D or light is SpotLight3D):
		return
	light.light_size = size_for(_level, float(light.get_meta(META_RADIUS, 0.0)))
