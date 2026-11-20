extends Node3D
class_name StreamedForestCell3D
## Scene content, independent from WorldStreamer3D; replace with a crafted
## PackedScene, a biome, or a level chunk without changing the streamer.

const Foliage = preload("res://addons/visual_quality/foliage_chunks.gd")

@export var world_seed: int = 20261120
@export var local_chunk_size: float = 14.0

var cell_coord: Vector2i = Vector2i.ZERO
var _quality_profile: int = 1
var _foliage: ChunkedFoliage3D


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


func set_quality(profile: int) -> void:
	_quality_profile = clampi(profile, 0, 2)
	if is_instance_valid(_foliage):
		_foliage.set_quality(_quality_profile)
