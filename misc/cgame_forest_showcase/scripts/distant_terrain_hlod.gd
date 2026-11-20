extends Node3D
## Collision-free, low-triangle distant terrain proxies for Aurora Forest.
##
## The native WorldPartition3D owns nearby authoritative terrain with physics.
## This independent visual-only HLOD layer fills the horizon with cheap mesh
## proxies, hiding them whenever the full streamed cell is available.
## Mesh creation is time-sliced on the main thread and uses the same height
## function, material and complete 1-meter tile borders as the near terrain.
##
## This is a terrain-specific runtime HLOD prototype, NOT Unreal's automatic
## HLOD scene merger, virtual geometry or texture streamer.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const TerrainPatch = preload("res://scripts/streamed_terrain_patch.gd")
const SharedAssets = preload("res://scripts/forest_shared_assets.gd")
const DistantCanopies = preload("res://scripts/distant_forest_canopies.gd")
const HLODCache = preload("res://scripts/distant_hlod_cache.gd")

const CELL_SIZE: int = 32
const GRID_WIDTH: int = 33
const LOD_STEP: int = 8
const MAX_BUILDS_PER_FRAME: int = 2
const MAX_BUILD_CPU_MS: float = 2.0
const MAX_RADIUS: int = 6

var streaming_world: WorldPartition3D
var observer: Node3D
var high_quality: bool = true

var _radius: int = MAX_RADIUS
var _proxies: Dictionary = {} # Vector2i -> MeshInstance3D.
var _lod_indices := PackedInt32Array()
var _dirty: bool = true
var _last_center: Vector2i = Vector2i.ZERO
var _center_valid: bool = false
var _built_total: int = 0
var _last_rebuild_cpu_ms: float = 0.0


func _ready() -> void:
    # Reuse the exact stitched index topology of the near-terrain LOD.
    # The temporary Node3D is never placed in the scene or processed.
    var source := TerrainPatch.new()
    _lod_indices = source._build_lod_indices(LOD_STEP)
    source.free()

    if streaming_world != null:
        streaming_world.cell_loaded.connect(_on_cell_loaded)
        streaming_world.cell_unloaded.connect(_on_cell_unloaded)
        streaming_world.observer_cell_changed.connect(_on_observer_moved)
    set_process(true)


func _exit_tree() -> void:
    _proxies.clear()


func _on_cell_loaded(cell: Vector2i) -> void:
    # Immediately prevent coplanar overlap / Z-fighting with accurate terrain.
    var proxy := _proxies.get(cell) as MeshInstance3D
    if proxy != null:
        proxy.visible = false
    _dirty = true


func _on_cell_unloaded(_cell: Vector2i) -> void:
    _dirty = true


func _on_observer_moved(_cell: Vector2i) -> void:
    _dirty = true


func set_high_quality(high: bool) -> void:
    high_quality = high
    _radius = MAX_RADIUS if high else 4
    _dirty = true


func _process(_delta: float) -> void:
    if streaming_world == null or observer == null:
        return

    var local: Vector3 = streaming_world.to_local(observer.global_position)
    var center: Vector2i = streaming_world.local_position_to_cell(local)
    if not _center_valid or center != _last_center:
        _center_valid = true
        _last_center = center
        _dirty = true

    if _dirty:
        _rebuild_visible_set(center)


func _rebuild_visible_set(center: Vector2i) -> void:
    var started_usec: int = Time.get_ticks_usec()
    var wanted: Dictionary = {}
    var built_this_frame: int = 0
    var missing: bool = false

    # Near-first HLOD scheduling: fill the gap next to the currently loading
    # collision tiles, then extend the view toward the distant horizon.
    for radius in range(_radius + 1):
        for dz in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if maxi(abs(dx), abs(dz)) != radius:
                    continue
                var cell := center + Vector2i(dx, dz)
                if streaming_world.get_cell_scene(cell).is_empty():
                    continue
                wanted[cell] = true

                var proxy := _proxies.get(cell) as MeshInstance3D
                var loaded: bool = streaming_world.is_cell_loaded(cell)
                if proxy != null:
                    proxy.visible = not loaded
                elif not loaded:
                    # A soft wall-time budget prevents multiple cold HLOD
                    # meshes being generated in one slow frame. The first
                    # missing cell always builds, so small budgets cannot
                    # starve HLOD creation altogether.
                    var elapsed_usec: int = Time.get_ticks_usec() - started_usec
                    if built_this_frame < MAX_BUILDS_PER_FRAME \
                            and (built_this_frame == 0 \
                            or float(elapsed_usec) < MAX_BUILD_CPU_MS * 1000.0):
                        proxy = _create_proxy(cell)
                        _proxies[cell] = proxy
                        built_this_frame += 1
                        _built_total += 1
                    else:
                        missing = true

    # Changing the observer region or graphics quality must release resources
    # outside the desired horizon. Avoid retaining permanent hidden nodes.
    for cell in _proxies.keys():
        if not wanted.has(cell):
            var old := _proxies[cell] as MeshInstance3D
            if old != null:
                old.queue_free()
            _proxies.erase(cell)

    _last_rebuild_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
    _dirty = missing


func _create_proxy(cell: Vector2i) -> MeshInstance3D:
    # A tile leaves the active horizon much more often than its geometry
    # changes. Reuse both GPU resources from a bounded LRU on revisits.
    var resources: Dictionary = HLODCache.lookup(cell)
    var mesh: ArrayMesh
    var canopies := DistantCanopies.new()
    if resources.is_empty():
        mesh = _build_proxy_mesh(cell)
        canopies.configure(cell)
        HLODCache.insert(cell, mesh, canopies.multimesh)
    else:
        mesh = resources["terrain"]
        canopies.configure(cell, resources["canopies"])

    var proxy := MeshInstance3D.new()
    proxy.name = "FarTerrain_%d_%d" % [cell.x, cell.y]
    proxy.mesh = mesh
    proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    # One shared low-poly MultiMesh batch preserves each tree's original
    # random position and size. Parent visibility handles exact HLOD
    # swaps atomically: no full-res / low-res crown double rendering.
    proxy.add_child(canopies)
    add_child(proxy)
    proxy.global_position = streaming_world.to_global(
        streaming_world.cell_to_local_position(cell))
    return proxy


func _build_proxy_mesh(cell: Vector2i) -> ArrayMesh:
    # Compact a 33x33 near-terrain vertex buffer to only the vertices used by
    # its stitched 8x index LOD. Outer 1m border vertices survive unchanged.
    var mapping: Dictionary = {}
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()

    for source_idx in _lod_indices:
        if not mapping.has(source_idx):
            var lx: int = source_idx % GRID_WIDTH
            var lz: int = int(source_idx / GRID_WIDTH)
            var wx: float = float(cell.x * CELL_SIZE + lx)
            var wz: float = float(cell.y * CELL_SIZE + lz)
            var normal: Vector3 = TerrainHeight.normal_at(wx, wz)
            var slope: float = clampf(1.0 - normal.y, 0.0, 1.0)
            var variation: float = 0.5 + 0.5 * sin(wx * 0.12 + wz * 0.09)
            var moss := Color(0.16, 0.27, 0.13)
            var soil := Color(0.21, 0.20, 0.13)

            mapping[source_idx] = vertices.size()
            vertices.push_back(Vector3(
                float(lx), TerrainHeight.height_at(wx, wz), float(lz)))
            normals.push_back(normal)
            colors.push_back(moss.lerp(soil,
                clampf(slope * 2.8 + variation * 0.12, 0.0, 1.0)))
            uvs.push_back(Vector2(wx, wz) * 0.08)
        indices.push_back(int(mapping[source_idx]))

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var result := ArrayMesh.new()
    result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    result.surface_set_material(0, SharedAssets.ground_material())
    return result


func get_proxy_for_cell(cell: Vector2i) -> MeshInstance3D:
    return _proxies.get(cell) as MeshInstance3D


func get_stats() -> Dictionary:
    var visible: int = 0
    var visible_canopies: int = 0
    for proxy in _proxies.values():
        if is_instance_valid(proxy) and proxy.visible:
            visible += 1
            var canopies := proxy.get_node_or_null("DistantForestCanopies") as MultiMeshInstance3D
            if canopies != null and canopies.multimesh != null:
                visible_canopies += canopies.multimesh.instance_count
    return {
        "radius": _radius,
        "allocated": _proxies.size(),
        "visible": visible,
        "visible_canopies": visible_canopies,
        "built_total": _built_total,
        "max_per_frame": MAX_BUILDS_PER_FRAME,
        "soft_cpu_budget_ms": MAX_BUILD_CPU_MS,
        "last_rebuild_cpu_ms": _last_rebuild_cpu_ms,
        "cache": HLODCache.get_stats()
    }
