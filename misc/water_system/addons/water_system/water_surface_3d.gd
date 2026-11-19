@tool
extends MeshInstance3D
class_name WaterSurface3D
## Bounded analytic water plane: GPU and CPU use the same 4 sine waves.
## Assumes an unrotated horizontal surface with unit scale.

const WATER_SHADER := preload("res://addons/water_system/water_surface.gdshader")

@export var surface_size := Vector2(64.0, 64.0)
@export_range(1, 128, 1) var subdivisions: int = 48
@export var wave_profile: WaterProfile
@export var animate: bool = true
@export var water_tint := Color(0.07, 0.35, 0.48, 1.0)
@export_range(0.0, 1.0, 0.01) var water_opacity := 0.85
@export_tool_button("Build Water Surface") var build_action := rebuild_surface

var _time_seconds := 0.0
var _water_material: ShaderMaterial


func _ready() -> void:
	if wave_profile == null:
		wave_profile = WaterProfile.make_default()
	rebuild_surface()
	_ensure_material()
	_sync_uniforms()
	set_process(true)


func rebuild_surface() -> bool:
	if not surface_size.is_finite() or surface_size.x <= 0.0 or surface_size.y <= 0.0:
		push_warning("WaterSurface3D requires finite positive surface dimensions")
		return false
	if subdivisions < 1 or subdivisions > 128:
		push_warning("WaterSurface3D subdivisions must be in range 1..128")
		return false
	var plane := PlaneMesh.new()
	plane.size = surface_size
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane
	return true


func _ensure_material() -> void:
	if material_override is ShaderMaterial and (material_override as ShaderMaterial).shader == WATER_SHADER:
		_water_material = material_override as ShaderMaterial
	else:
		_water_material = ShaderMaterial.new()
		_water_material.shader = WATER_SHADER
		material_override = _water_material


func _sync_uniforms() -> bool:
	if wave_profile == null:
		return false
	if not wave_profile.validation_error().is_empty():
		return false
	_ensure_material()
	for index in WaterProfile.MAX_WAVES:
		var packed := wave_profile.wave_parameters(index)
		_water_material.set_shader_parameter("wave_%d" % index, packed["wave"])
		_water_material.set_shader_parameter("motion_%d" % index, packed["motion"])
	_water_material.set_shader_parameter("water_time", _time_seconds)
	_water_material.set_shader_parameter("water_tint", water_tint)
	_water_material.set_shader_parameter("water_opacity", water_opacity)
	return true


func set_simulation_time(time_seconds: float) -> bool:
	if not is_finite(time_seconds):
		return false
	_time_seconds = time_seconds
	return _sync_uniforms()


func get_simulation_time() -> float:
	return _time_seconds


func sample_at(world_position: Vector3, time_override: float = INF) -> Dictionary:
	if wave_profile == null:
		return {"ok": false, "error": "Missing WaterProfile", "height": 0.0, "normal": Vector3.UP}
	if not world_position.is_finite():
		return {"ok": false, "error": "Nonfinite world position", "height": 0.0, "normal": Vector3.UP}
	# Buoyancy must not act beyond the finite rendered water surface.
	if (absf(world_position.x - global_position.x) > surface_size.x * 0.5
			or absf(world_position.z - global_position.z) > surface_size.y * 0.5):
		return {"ok": false, "error": "Outside WaterSurface3D bounds", "height": 0.0, "normal": Vector3.UP}
	var time_seconds: float = _time_seconds if is_inf(time_override) else time_override
	var result := wave_profile.sample(Vector2(world_position.x, world_position.z), time_seconds)
	if result["ok"]:
		result["height"] += global_position.y
	return result


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and animate and is_finite(delta) and delta >= 0.0:
		_time_seconds += delta
	_sync_uniforms()
