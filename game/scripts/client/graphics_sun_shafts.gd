extends MeshInstance3D
## Screen-space volumetric sun shafts (god rays), the Unreal "Light Shafts" /
## CryEngine "Sun Shafts" technique: one fullscreen additive pass that marches
## towards the projected sun and streaks occluders through hazy air.
## Forward+ High/Ultra only; Performance/Balanced/Compatibility pay nothing
## (node hidden, no draw). The sun direction/colour is pushed only on change.

const SHADER := preload("res://assets/shaders/sun_shafts.gdshader")
const NODE_NAME := &"SunShafts"

var sun: DirectionalLight3D
var _mat: ShaderMaterial
var _last_dir := Vector3.ZERO
var _last_color := Color(0, 0, 0, 0)


static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = rendering_method == "forward_plus" and tier >= 2
	return {
		"enabled": enabled,
		"samples": 48 if tier == 3 else 32,
		"intensity": 0.42 if tier == 3 else 0.34,
		"decay": 0.97 if tier == 3 else 0.96,
	}


## Shaft tint: sun colour * energy, dimmed below the horizon (night/moon stays subtle).
static func shaft_color(light_color: Color, energy: float, sun_dir: Vector3) -> Color:
	var horizon: float = clampf((sun_dir.normalized().y + 0.05) / 0.25, 0.0, 1.0)
	var e: float = clampf(energy, 0.0, 2.0) * horizon
	return Color(light_color.r * e, light_color.g * e, light_color.b * e)


## Idempotent: creates/updates/hides the pass under the active camera.
static func apply(camera: Camera3D, sun_light: DirectionalLight3D, level: int,
		rendering_method: String) -> void:
	if camera == null:
		return
	var policy: Dictionary = settings(level, rendering_method)
	var node := camera.get_node_or_null(NodePath(NODE_NAME)) as MeshInstance3D
	if not bool(policy["enabled"]) or sun_light == null:
		if node != null:
			node.visible = false
		return
	if node == null:
		node = (load("res://scripts/client/graphics_sun_shafts.gd") as GDScript).new()
		node.name = NODE_NAME
		camera.add_child(node)
	node.set("sun", sun_light)
	node.visible = true
	var mat := node.material_override as ShaderMaterial
	mat.set_shader_parameter("samples", int(policy["samples"]))
	mat.set_shader_parameter("intensity", float(policy["intensity"]))
	mat.set_shader_parameter("decay", float(policy["decay"]))


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _process(_delta: float) -> void:
	if not visible or sun == null or not is_instance_valid(sun):
		return
	# Directional lights shine along -Z; the shader wants the direction towards the sun.
	var to_sun: Vector3 = sun.global_transform.basis.z.normalized()
	if not to_sun.is_equal_approx(_last_dir):
		_last_dir = to_sun
		_mat.set_shader_parameter("sun_dir_world", to_sun)
	var c: Color = shaft_color(sun.light_color, sun.light_energy, to_sun)
	if not c.is_equal_approx(_last_color):
		_last_color = c
		_mat.set_shader_parameter("sun_color", Vector3(c.r, c.g, c.b))
