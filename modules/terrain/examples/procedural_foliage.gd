extends Node3D
## Demonstrates placing a large number of mesh instances on sampled terrain.
## Foliage is deterministic for a seed, and placement obeys slope and height filters.

@export var terrain_data: TerrainHeightmap
@export var foliage_mesh: Mesh
@export var foliage_material: Material
@export_range(0.01, 100.0, 0.01) var cell_size: float = 2.0
@export_range(0.01, 100.0, 0.01) var spacing: float = 5.0
@export_range(0.0, 1.0, 0.01) var jitter: float = 0.75
@export_range(0.0, 90.0, 0.1) var max_slope_degrees: float = 35.0
@export var min_height: float = -1000.0
@export var max_height: float = 1000.0
@export var seed: int = 12345


func _ready() -> void:
    if terrain_data == null or foliage_mesh == null:
        return
    var points := terrain_data.scatter_points(seed, spacing, jitter,
            max_slope_degrees, min_height, max_height, cell_size)
    if points.is_empty():
        return

    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = foliage_mesh
    multimesh.instance_count = points.size()
    for i in range(points.size()):
        multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))

    var instances := MultiMeshInstance3D.new()
    instances.multimesh = multimesh
    instances.material_override = foliage_material
    add_child(instances)
