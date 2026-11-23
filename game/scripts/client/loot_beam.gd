extends RefCounted
## Loot beams by value (Diablo IV / Borderlands): a light column above notable
## loot so it reads from across the map. Display-only, from snapshot flags.

const SHADER := preload("res://assets/shaders/loot_beam.gdshader")
const NODE_NAME := &"LootBeam"


## Beam colour for a bag; alpha 0 means no beam (ordinary public loot).
static func color_for(bag: Dictionary) -> Color:
	# World geometry still represents protected loot; valuable beams only
	# advertise rewards to people permitted to claim them.
	if bool(bag.get("reserved", false)) and not bool(bag.get("can_loot", false)):
		return Color(0, 0, 0, 0)
	if bool(bag.get("raid", false)):
		return Color(1.0, 0.55, 0.12, 1.0) # Legendary orange.
	if bool(bag.get("horde_cache", false)):
		return Color(0.72, 0.35, 1.0, 1.0) # Epic purple.
	if bool(bag.get("supply_drop", false)):
		return Color(0.25, 0.65, 1.0, 1.0) # Rare blue.
	if bool(bag.get("reserved", false)) and bool(bag.get("can_loot", false)):
		return Color(1.0, 0.85, 0.35, 0.6) # Your party's loot: soft gold.
	return Color(0, 0, 0, 0)


static func make() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = NODE_NAME
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 9.0)
	beam.mesh = quad
	beam.position.y = 4.6
	var m := ShaderMaterial.new()
	m.shader = SHADER
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	return beam


## Called on every snapshot update; only touches the material when the colour changes.
static func update(root: Node, bag: Dictionary) -> void:
	var beam := root.get_node_or_null(NodePath(NODE_NAME)) as MeshInstance3D
	if beam == null:
		return
	var c: Color = color_for(bag)
	beam.visible = c.a > 0.0
	if not beam.visible:
		return
	var m := beam.material_override as ShaderMaterial
	if m.get_shader_parameter("beam_color") != c:
		m.set_shader_parameter("beam_color", c)
