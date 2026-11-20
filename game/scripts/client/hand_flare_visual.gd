extends Node3D
## 3D visual only; state comes from server snapshots.
var _active: bool = false


func _ready() -> void:
	position = Vector3(0.38, 1.45, 0.1)
	var light := OmniLight3D.new()
	light.name = "FlareLight"
	light.light_color = Color(1.0, 0.55, 0.24)
	light.light_energy = 2.0
	light.omni_range = 13.0
	light.shadow_enabled = false
	add_child(light)
	var ember := MeshInstance3D.new()
	ember.name = "FlareEmber"
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	ember.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.4, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.15)
	mat.emission_energy_multiplier = 2.5
	ember.material_override = mat
	add_child(ember)
	set_burning(_active)


func set_burning(active: bool) -> void:
	_active = active
	visible = active
