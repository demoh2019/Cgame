extends Node3D
## Network-display-only ground warning. This has no collision, damage, or AI.
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
var _warning: Dictionary = {}
var _disc: MeshInstance3D


func _ready() -> void:
	_disc = MeshInstance3D.new()
	_disc.name = "LightningDangerDisk"
	var disk := CylinderMesh.new()
	disk.top_radius = StormLightning.RADIUS
	disk.bottom_radius = StormLightning.RADIUS
	disk.height = 0.025
	_disc.mesh = disk
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.67, 0.39, 1.0, 0.36)
	mat.no_depth_test = false
	_disc.material_override = mat
	add_child(_disc)
	visible = false


func set_warning(warning: Dictionary) -> void:
	_warning = warning
	visible = false
	if warning.is_empty():
		return
	for key in ["x", "y", "z", "at"]:
		if not warning.has(key) or not is_finite(float(warning[key])):
			return
	var radius: float = float(warning.get("radius", StormLightning.RADIUS))
	if radius <= 0.0 or radius > StormLightning.RADIUS:
		return
	position = Vector3(float(warning["x"]), float(warning["y"]) + 0.05,
		float(warning["z"]))
	visible = true
