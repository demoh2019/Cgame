extends Node3D
class_name StreamedForestCell3D
## Scene content, independent from WorldStreamer3D; replace with a crafted
## PackedScene, a biome, or a level chunk without changing the streamer.

const Foliage = preload("res://addons/visual_quality/foliage_chunks.gd")

signal stream_state_changed()

@export var world_seed: int = 20261120
@export var local_chunk_size: float = 14.0

var cell_coord: Vector2i = Vector2i.ZERO
var _quality_profile: int = 1
var _foliage: ChunkedFoliage3D
var beacon_activated: bool = false
var _beacon: MeshInstance3D


func configure_stream_cell(coord: Vector2i) -> void:
	cell_coord = coord


func _ready() -> void:
	_foliage = Foliage.new()
	_foliage.name = "GPUForest"
	_foliage.chunks_per_axis = 1
	_foliage.chunk_size = local_chunk_size
	_foliage.trees_per_chunk = 24
	_foliage.world_seed = Foliage.cell_seed(world_seed, cell_coord.x, cell_coord.y)
	_foliage.clear_radius = 12.0 if cell_coord == Vector2i.ZERO else 0.0
	add_child(_foliage)
	_foliage.set_quality(_quality_profile)
	_create_beacon()


func set_quality(profile: int) -> void:
	_quality_profile = clampi(profile, 0, 2)
	if is_instance_valid(_foliage):
		_foliage.set_quality(_quality_profile)


func get_stream_cell_coord() -> Vector2i:
	return cell_coord


func _create_beacon() -> void:
	_beacon = MeshInstance3D.new()
	_beacon.name = "PersistentForestBeacon"
	_beacon.position = Vector3(2.0, 1.3, -2.0)
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.10
	mesh.radial_segments = 12
	mesh.rings = 6
	_beacon.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.emission_enabled = true
	material.roughness = 0.3
	_beacon.material_override = material
	add_child(_beacon)
	_update_beacon_visual()


func get_beacon_world_position() -> Vector3:
	if is_instance_valid(_beacon):
		return _beacon.global_position
	return to_global(Vector3(2.0, 1.3, -2.0))


func try_activate_beacon(player_world_position: Vector3, radius: float = 2.8) -> bool:
	if beacon_activated or radius <= 0.0:
		return false
	if player_world_position.distance_squared_to(get_beacon_world_position()) > radius * radius:
		return false
	beacon_activated = true
	_update_beacon_visual()
	stream_state_changed.emit()
	return true


func _update_beacon_visual() -> void:
	if not is_instance_valid(_beacon):
		return
	var material: StandardMaterial3D = _beacon.material_override as StandardMaterial3D
	if beacon_activated:
		material.albedo_color = Color(0.27, 1.0, 0.35)
		material.emission = Color(0.10, 0.80, 0.18)
		material.emission_energy_multiplier = 2.5
	else:
		material.albedo_color = Color(0.98, 0.45, 0.12)
		material.emission = Color(0.96, 0.28, 0.06)
		material.emission_energy_multiplier = 1.6


## Store only modified state; empty dict means default/unmodified.
func save_stream_state() -> Dictionary:
	if beacon_activated:
		return {"activated": true}
	return {}


func load_stream_state(state: Dictionary) -> void:
	beacon_activated = state.get("activated", false) == true
	_update_beacon_visual()
