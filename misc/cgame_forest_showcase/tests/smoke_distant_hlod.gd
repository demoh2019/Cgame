extends SceneTree
## Headless integration regression for simplified distant terrain proxies:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_distant_hlod.gd

const HLOD = preload("res://scripts/distant_terrain_hlod.gd")
const Height = preload("res://scripts/terrain_height.gd")
const MAX_FRAMES: int = 450


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Distant terrain HLOD smoke FAILED: " + reason)
    quit(1)


func _wait_proxy(manager: Node3D, cell: Vector2i) -> MeshInstance3D:
    for i in range(MAX_FRAMES):
        var proxy: MeshInstance3D = manager.call("get_proxy_for_cell", cell)
        if proxy != null:
            return proxy
        await process_frame
    return null


func _wait_loaded(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell):
            return true
        await process_frame
    return false


func _run() -> void:
    var observer := Node3D.new()
    observer.name = "HLODTestObserver"
    root.add_child(observer)

    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    stream.max_instances_per_frame = 1
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    for x in range(7):
        stream.set_cell_scene(Vector2i(x, 0), "res://cells/forest_cell.tscn")

    var manager := Node3D.new()
    manager.name = "HLODTestManager"
    manager.set_script(HLOD)
    manager.set("streaming_world", stream)
    manager.set("observer", observer)
    root.add_child(manager)

    var far := Vector2i(3, 0)
    var far_proxy: MeshInstance3D = await _wait_proxy(manager, far)
    if far_proxy == null:
        _fail("distant terrain proxy was not created")
        return
    if not far_proxy.visible:
        _fail("distant proxy was hidden with no full-detail cell loaded")
        return
    if not await _wait_loaded(stream, Vector2i.ZERO):
        _fail("primary streamed terrain did not load")
        return
    if stream.is_cell_loaded(far):
        _fail("unexpected full-detail terrain at distant HLOD position")
        return

    var mesh: Mesh = far_proxy.mesh
    var arrays: Array = mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    if vertices.size() >= 1089 or vertices.size() < 129:
        _fail("proxy is not a compact 33x33-border stitched LOD")
        return
    if indices.size() != 176 * 3:
        _fail("proxy triangle count differs from stitched terrain 8x LOD")
        return
    for i in range(indices.size()):
        if indices[i] < 0 or indices[i] >= vertices.size():
            _fail("proxy LOD contains invalid remapped vertex indices")
            return

    # Every outer 1m sample must match both high-resolution terrain height
    # and analytic normal, even when the distant proxy uses 8m interior steps.
    var border_count: int = 0
    for v in range(vertices.size()):
        var p: Vector3 = vertices[v]
        var edge: bool = absf(p.x) < 0.001 or absf(p.x - 32.0) < 0.001 \
            or absf(p.z) < 0.001 or absf(p.z - 32.0) < 0.001
        if not edge:
            continue
        border_count += 1
        var wx: float = float(far.x * 32) + p.x
        var wz: float = float(far.y * 32) + p.z
        if absf(p.y - Height.height_at(wx, wz)) > 0.0001:
            _fail("far proxy has a cracked heightfield border")
            return
        if normals[v].distance_to(Height.normal_at(wx, wz)) > 0.0001:
            _fail("far proxy has a mismatched border normal")
            return
    if border_count != 4 * 32:
        _fail("far proxy does not preserve every 1m border vertex")
        return
    for node in manager.get_children():
        if node is StaticBody3D or node is CollisionShape3D:
            _fail("visual HLOD unexpectedly owns a physics collider")
            return

    observer.position.x = 3.0 * 32.0 + 1.0
    if not await _wait_loaded(stream, far):
        _fail("accurate streamed cell failed to replace distant proxy")
        return
    if far_proxy.visible:
        _fail("proxy overlapped full-detail streamed ground")
        return

    observer.position.x = 0.0
    if not await _wait_loaded(stream, Vector2i.ZERO):
        _fail("origin full-detail tile did not reload")
        return
    for i in range(3):
        await process_frame
    if stream.is_cell_loaded(far) or not far_proxy.visible:
        _fail("distant proxy did not reappear when full cell unloaded")
        return

    manager.call("set_high_quality", false)
    for i in range(4):
        await process_frame
    var stats: Dictionary = manager.call("get_stats")
    if stats["radius"] != 4 or stats["allocated"] > 81:
        _fail("performance profile failed to shrink the distant horizon")
        return
    if manager.call("get_proxy_for_cell", Vector2i(6, 0)) != null:
        _fail("performance profile retained an out-of-radius proxy")
        return

    print("Distant terrain HLOD smoke PASSED: compact border-stitch mesh, render/physics separation, streaming handoff and quality radius")
    quit(0)
