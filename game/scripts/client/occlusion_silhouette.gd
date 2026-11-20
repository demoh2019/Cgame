extends RefCounted
## Keeps characters readable behind buildings and trees (Diablo / PoE X-ray):
## a material_overlay pass with an inverted depth test draws a tinted rim only
## where the character is hidden. One shared material; no extra nodes.

const SHADER := preload("res://assets/shaders/occlusion_silhouette.gdshader")
const SELF_TINT := Color(0.35, 0.85, 1.0, 0.55)

static var _materials: Dictionary = {} # Color -> ShaderMaterial (shared)


static func material_for(tint: Color) -> ShaderMaterial:
	if not _materials.has(tint):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("tint", tint)
		m.render_priority = 1
		_materials[tint] = m
	return _materials[tint]


## Applies (or with enabled=false removes) the overlay on every mesh of a model.
static func apply(model: Node, tint: Color = SELF_TINT, enabled: bool = true) -> int:
	if model == null:
		return 0
	var count := 0
	var overlay: Material = material_for(tint) if enabled else null
	for found in model.find_children("*", "GeometryInstance3D", true, false):
		(found as GeometryInstance3D).material_overlay = overlay
		count += 1
	return count
