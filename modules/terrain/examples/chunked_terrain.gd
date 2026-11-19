extends Node3D
## Demonstration of camera-centered chunk creation and release.
## Not a production World Partition system: chunks come from one in-memory heightmap
## and mixed-LOD borders require stitch meshes or skirts to avoid cracks.

@export var terrain_data: TerrainHeightmap
@export var view_camera: Camera3D
@export var terrain_material: Material
@export_range(1, 128, 1) var chunk_cells: int = 32
@export_range(1, 16, 1) var visible_radius: int = 3
@export_range(0.01, 100.0, 0.01) var cell_size: float = 2.0
@export var use_distance_lod: bool = true

var _chunks: Dictionary = {}
var _chunk_strides: Dictionary = {}


func _ready() -> void:
    if terrain_data != null:
        terrain_data.changed.connect(_on_terrain_changed)


func _exit_tree() -> void:
    if terrain_data != null and terrain_data.changed.is_connected(_on_terrain_changed):
        terrain_data.changed.disconnect(_on_terrain_changed)


func _on_terrain_changed() -> void:
    # Conservative invalidation. Production code should invalidate only affected chunks.
    _clear_chunks()


func _clear_chunks() -> void:
    for instance in _chunks.values():
        instance.queue_free()
    _chunks.clear()
    _chunk_strides.clear()


func _process(_delta: float) -> void:
    if terrain_data == null or view_camera == null:
        return

    var cells := terrain_data.dimensions - Vector2i.ONE
    var cols := ceili(float(cells.x) / chunk_cells)
    var rows := ceili(float(cells.y) / chunk_cells)
    var camera_local := to_local(view_camera.global_position)
    var center := Vector2i(
        floori(camera_local.x / (chunk_cells * cell_size)),
        floori(camera_local.z / (chunk_cells * cell_size))
    )

    var needed := {}
    for cz in range(maxi(0, center.y - visible_radius), mini(rows, center.y + visible_radius + 1)):
        for cx in range(maxi(0, center.x - visible_radius), mini(cols, center.x + visible_radius + 1)):
            var key := Vector2i(cx, cz)
            var origin := key * chunk_cells
            var count := Vector2i(mini(chunk_cells, cells.x - origin.x),
                    mini(chunk_cells, cells.y - origin.y))
            var chunk_distance := maxi(absi(cx - center.x), absi(cz - center.y))

            var stride := 1
            if use_distance_lod:
                stride = 1 if chunk_distance <= 1 else (2 if chunk_distance <= 3 else 4)
                # Partial edge chunks may not divide evenly by the preferred stride.
                while stride > 1 and (count.x % stride != 0 or count.y % stride != 0):
                    stride = int(stride / 2)

            needed[key] = true
            if _chunks.has(key) and _chunk_strides[key] == stride:
                continue

            if _chunks.has(key):
                _chunks[key].queue_free()

            var mesh := terrain_data.build_chunk_mesh(origin, count, stride, cell_size)
            if mesh == null:
                continue

            var instance := MeshInstance3D.new()
            instance.mesh = mesh
            instance.material_override = terrain_material
            instance.position = Vector3(origin.x * cell_size, 0, origin.y * cell_size)
            add_child(instance)
            _chunks[key] = instance
            _chunk_strides[key] = stride

    for key in _chunks.keys():
        if not needed.has(key):
            _chunks[key].queue_free()
            _chunks.erase(key)
            _chunk_strides.erase(key)
