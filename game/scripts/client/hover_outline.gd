extends RefCounted
## Hover highlight for what the mouse points at (UE custom-depth outlines, Diablo /
## Path of Exile target highlight): an inverted-hull material_overlay on the model
## nearest the cursor's ground point. Display-only; one overlay at a time.

const SHADER := preload("res://assets/shaders/hover_outline.gdshader")
const PICK_RADIUS := 1.6

static var _materials: Dictionary = {}
var _current: Node = null


static func color_for(kind: String) -> Color:
	match kind:
		"zombie":
			return Color(1.0, 0.22, 0.18, 1.0)
		"bag":
			return Color(1.0, 0.82, 0.3, 1.0)
		"player":
			return Color(0.35, 0.85, 1.0, 1.0)
	return Color(0, 0, 0, 0)


static func material_for(kind: String) -> ShaderMaterial:
	if not _materials.has(kind):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("outline_color", color_for(kind))
		_materials[kind] = m
	return _materials[kind]


static func _set_overlay(node: Node, material: Material) -> void:
	if node == null or not is_instance_valid(node):
		return
	for found in node.find_children("*", "GeometryInstance3D", true, false):
		# Never steal an overlay another system owns (X-ray silhouette, corpse burn).
		var g := found as GeometryInstance3D
		if g is Label3D or g is SpriteBase3D or g.name == &"LootBeam":
			continue # Text, sprites and light columns have no hull to outline.
		if material == null:
			if g.material_overlay != null and g.material_overlay.get_meta("hover_outline", false):
				g.material_overlay = null
		elif g.material_overlay == null:
			g.material_overlay = material


## `target` is {"node": Node3D, "kind": String} or empty.
func set_target(target: Dictionary) -> void:
	var node: Node = target.get("node", null)
	if node == _current:
		return
	_set_overlay(_current, null)
	_current = node
	var kind: String = str(target.get("kind", ""))
	if node != null and color_for(kind).a > 0.0:
		var m := material_for(kind)
		m.set_meta("hover_outline", true)
		_set_overlay(node, m)
