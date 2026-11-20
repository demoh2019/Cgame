extends SceneTree
## Headless integration regression for simplified distant terrain proxies:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_distant_hlod.gd

const HLOD = preload("res://scripts/distant_terrain_hlod.gd")
const Height = preload("res://scripts/terrain_height.gd")
const HLODCache = preload("res://scripts/distant_hlod_cache.gd")
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
    HLODCache.clear()
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
    var impostors := far_proxy.get_node_or_null("DistantForestCanopies") as MultiMeshInstance3D
    if impostors == null or impostors.multimesh == null:
        _fail("distant terrain has no instanced forest canopy batch")
        return
    if impostors.multimesh.instance_count < 1 or impostors.multimesh.instance_count > 54:
        _fail("distant forest instance count exceeds tree placement budget")
        return
    var far_crown_mesh := impostors.multimesh.mesh as SphereMesh
    if far_crown_mesh == null or far_crown_mesh.radial_segments != 5 or far_crown_mesh.rings != 2:
        _fail("distant forest did not use the shared low-poly canopy mesh")
        return
    if impostors.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
        _fail("far canopy should not cast costly full-resolution shadows")
        return

    var second_proxy: MeshInstance3D = await _wait_proxy(manager, Vector2i(4, 0))
    if second_proxy == null:
        _fail("second distant forest proxy did not load")
        return
    var other_canopies := second_proxy.get_node_or_null("DistantForestCanopies") as MultiMeshInstance3D
    if other_canopies == null or other_canopies.multimesh == null:
        _fail("second distant forest has no instanced canopy batch")
        return
    if other_canopies.multimesh.mesh != impostors.multimesh.mesh:
        _fail("distant cells failed to share a single low-poly canopy mesh")
        return
    if other_canopies.multimesh == impostors.multimesh:
        _fail("distant cells must own distinct transform batches")
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

    # A correct HLOD handoff preserves every procedural tree's transform.
    # This compares against the ACTUAL full-res game scene, not a reimplementation.
    var near_root: Node3D = stream.get_cell_node(far)
    if near_root == null:
        _fail("native streamer lost the loaded full-detail tile")
        return
    var near_canopies := near_root.get_node_or_null("WindCanopies") as MultiMeshInstance3D
    if near_canopies == null or near_canopies.multimesh == null:
        _fail("full-detail forest is missing tree canopy instances")
        return
    if impostors.multimesh.instance_count != near_canopies.multimesh.instance_count:
        _fail("far forest tree count disagrees with near forest")
        return
    for i in range(impostors.multimesh.instance_count):
        var low: Transform3D = impostors.multimesh.get_instance_transform(i)
        var high: Transform3D = near_canopies.multimesh.get_instance_transform(i)
        if not low.is_equal_approx(high):
            _fail("tree %d changes position/orientation at full-detail handoff" % i)
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
    var visible_stats: Dictionary = manager.call("get_stats")
    if int(visible_stats["visible_canopies"]) < impostors.multimesh.instance_count:
        _fail("distant canopy visibility statistics are incorrect")
        return

    manager.call("set_high_quality", false)
    for i in range(4):
        await process_frame
    var stats: Dictionary = manager.call("get_stats")
    if stats["radius"] != 4 or stats["allocated"] > 81:
        _fail("performance profile failed to shrink the distant horizon")
        return
    if float(stats["last_rebuild_cpu_ms"]) < 0.0 \
            or float(stats["soft_cpu_budget_ms"]) != 2.0:
        _fail("distant HLOD CPU build telemetry or soft budget is invalid")
        return
    if manager.call("get_proxy_for_cell", Vector2i(6, 0)) != null:
        _fail("performance profile retained an out-of-radius proxy")
        return

    # Cross the HLOD visibility horizon and return. Both expensive
    # resources must be reused without another terrain/foliage regeneration.
    var old_terrain_mesh: Mesh = far_proxy.mesh
    var old_canopy_batch: MultiMesh = impostors.multimesh
    var hits_before: int = int(HLODCache.get_stats()["hits"])
    observer.position.x = -6.0 * 32.0
    for i in range(5):
        await process_frame
    if manager.call("get_proxy_for_cell", far) != null:
        _fail("HLOD node was not evicted when its cell left the horizon")
        return
    observer.position.x = 0.0
    var revisited: MeshInstance3D = await _wait_proxy(manager, far)
    if revisited == null:
        _fail("HLOD proxy was not reconstructed after returning")
        return
    var new_canopies := revisited.get_node_or_null("DistantForestCanopies") as MultiMeshInstance3D
    if new_canopies == null or revisited.mesh != old_terrain_mesh \
            or new_canopies.multimesh != old_canopy_batch:
        _fail("HLOD cache did not reuse both terrain mesh and canopy MultiMesh")
        return
    var cache_stats: Dictionary = HLODCache.get_stats()
    if int(cache_stats["hits"]) <= hits_before or int(cache_stats["entries"]) > 96:
        _fail("HLOD cache failed to record a hit or respect its memory limit")
        return

    print("Distant terrain/forest HLOD smoke PASSED: stitched terrain, canopy transforms, full-detail handoff, profile radius and resource reuse")
    quit(0)
