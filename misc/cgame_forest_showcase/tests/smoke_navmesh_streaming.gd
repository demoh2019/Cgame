extends SceneTree
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_navmesh_streaming.gd
## Test actual clearance-filtered NavigationMesh polygons and server paths across two
## contiguous forest-cell NavigationRegions plus native priority tier changes.

const FOREST: String = "res://cells/forest_cell.tscn"
const TerrainHeight = preload("res://scripts/terrain_height.gd")
const FRAMES: int = 420
const REMOTE: Vector2i = Vector2i(1, 0)


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Forest NavMesh streaming smoke FAILED: " + message)
    quit(1)


func _wait_loaded(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(FRAMES):
        if stream.get_cell_instance(cell) != null:
            return true
        await process_frame
    return false


func _wait_nav(stream: WorldPartition3D, cell: Vector2i, enabled: bool) -> bool:
    for i in range(FRAMES):
        stream.update_streaming()
        if stream.is_cell_navigation_active(cell) == enabled:
            var scene: Node3D = stream.get_cell_instance(cell)
            if scene != null and scene.get("streaming_navigation_active") == enabled:
                if not enabled or stream.is_cell_navigation_ready(cell):
                    return true
        await physics_frame
        await process_frame
    return false


func _region(stream: WorldPartition3D, cell: Vector2i) -> NavigationRegion3D:
    var scene: Node3D = stream.get_cell_instance(cell)
    if scene == null:
        return null
    return scene.get_node_or_null("StreamingNavigationRegion") as NavigationRegion3D


func _run() -> void:
    if not ResourceLoader.exists(FOREST):
        _fail("streamed forest scene is missing")
        return

    var observer := Node3D.new()
    root.add_child(observer)
    observer.position = Vector3(8, 1, 8)

    var stream := WorldPartition3D.new()
    stream.name = "NavMeshTest"
    stream.cell_size = 32.0
    stream.load_radius = 1
    stream.unload_radius = 2
    stream.detail_radius = 0
    stream.max_detail_transitions_per_frame = 2
    stream.physics_radius = 0
    stream.navigation_radius = 0
    stream.navigation_hysteresis_cells = 0
    stream.max_navigation_transitions_per_frame = 1
    stream.max_instances_per_frame = 1
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    stream.set_cell_scene(Vector2i.ZERO, FOREST)
    stream.set_cell_scene(REMOTE, FOREST)
    if not await _wait_loaded(stream, Vector2i.ZERO):
        _fail("local navigation scene failed to load")
        return
    if not await _wait_loaded(stream, REMOTE):
        _fail("remote navigation scene failed to load")
        return

    if not await _wait_nav(stream, Vector2i.ZERO, true):
        _fail("local streamed navigation tile was never ready")
        return
    if stream.is_cell_navigation_active(REMOTE) or _region(stream, REMOTE) != null:
        _fail("remote visual scene unexpectedly allocated a live NavMesh")
        return
    var home: NavigationRegion3D = _region(stream, Vector2i.ZERO)
    if home == null or home.navigation_mesh == null:
        _fail("near forest scene lacks NavigationRegion3D and NavigationMesh")
        return
    var home_polygons: int = home.navigation_mesh.get_polygon_count()
    if home_polygons <= 0 or home_polygons >= 512:
        _fail("near NavMesh should contain obstacle-carved 16x16 terrain triangles")
        return
    var home_cell: Node3D = stream.get_cell_instance(Vector2i.ZERO)
    var home_blockers: PackedVector3Array = home_cell.get("navigation_blockers")
    if home_blockers.is_empty():
        _fail("near forest navigation was not provided any obstacle footprints")
        return

    # A low-priority source preloads visuals only, without activating navigation.
    if not stream.set_streaming_source("quest", Vector3(42, 0, 8), 0, 0):
        _fail("could not add background streaming source")
        return
    for i in range(3):
        await physics_frame
        await process_frame
    if stream.is_cell_navigation_active(REMOTE):
        _fail("background source incorrectly enabled remote NavMesh")
        return

    # An urgent travel target must activate both near LOD and the NavMesh.
    if not stream.set_streaming_source("arrival", Vector3(42, 0, 8), 0, 3):
        _fail("could not add urgent navigation source")
        return
    if not await _wait_nav(stream, REMOTE, true):
        _fail("urgent source failed to enable the remote NavigationRegion3D")
        return
    if not stream.is_streaming_source_navigation_ready("arrival"):
        _fail("urgent source bypassed the navigation readiness fence")
        return
    var far: NavigationRegion3D = _region(stream, REMOTE)
    if far == null or far.navigation_mesh == null or not far.enabled:
        _fail("urgent destination does not have an enabled NavigationRegion3D")
        return
    var far_polygons: int = far.navigation_mesh.get_polygon_count()
    if far_polygons <= 0 or far_polygons >= 512:
        _fail("destination NavMesh should be tessellated and obstacle-carved")
        return
    for i in range(4):
        await physics_frame
    var start := Vector3(14, TerrainHeight.height_at(14, 16) + 0.2, 16)
    var goal := Vector3(50, TerrainHeight.height_at(50, 16) + 0.2, 16)
    var path: PackedVector3Array = NavigationServer3D.map_get_path(
        root.get_world_3d().navigation_map, start, goal, true, 1)
    if path.size() < 2 or path[path.size() - 1].distance_to(goal) > 4.0:
        _fail("NavigationServer3D did not connect adjacent streamed terrain tiles")
        return

    # An actual forest stalker must consume a native steering permit and
    # retrieve a synchronized NavigationServer3D path across the two cells.
    var target := Node3D.new()
    root.add_child(target)
    target.global_position = Vector3(
        34, TerrainHeight.height_at(34, 16) + 1.1, 16)
    var enemy := CharacterBody3D.new()
    enemy.set_script(preload("res://scripts/forest_stalker.gd"))
    root.add_child(enemy)
    enemy.call("configure", "navmesh_stalker", target, Vector3(
        24, TerrainHeight.height_at(24, 16) + 1.1, 16), stream)
    enemy.call("set_encounter_active", true)
    for i in range(12):
        await physics_frame
    await process_frame
    if int(enemy.get("navmesh_path_queries")) < 1 \
            or int(enemy.get("navmesh_path_successes")) < 1:
        _fail("real stalker did not obtain a streamed cross-cell NavMesh path")
        return
    enemy.queue_free()
    await process_frame
    if stream.has_navigation_agent("navmesh_stalker"):
        _fail("removed NavMesh stalker kept an obsolete native agent ID")
        return

    stream.remove_streaming_source("arrival")
    if not await _wait_nav(stream, REMOTE, false):
        _fail("removing the urgent source left distant navigation active")
        return
    far = _region(stream, REMOTE)
    if far != null and far.enabled:
        _fail("remote NavigationRegion3D remained enabled while dormant")
        return
    if not stream.is_cell_loaded(REMOTE):
        _fail("NavMesh demotion unloaded remote visuals")
        return
    if stream.is_streaming_source_navigation_ready("arrival"):
        _fail("removed urgent navigation source reported ready")
        return

    if not stream.pin_cell(REMOTE):
        _fail("could not pin a remote navigation hub")
        return
    if not await _wait_nav(stream, REMOTE, true):
        _fail("pinning the hub did not reactivate its navigation")
        return
    stream.unpin_cell(REMOTE)
    if not await _wait_nav(stream, REMOTE, false):
        _fail("unpinning the hub failed to demote its NavMesh")
        return

    stream.navigation_radius = -1
    if not await _wait_nav(stream, REMOTE, true):
        _fail("legacy -1 navigation radius did not reactivate loaded cells")
        return
    if stream.get_navigation_active_cell_count() != 2:
        _fail("active navigation-cell counter expected 2 live cells")
        return

    print("Forest NavMesh streaming smoke PASSED: real terrain nav polygons, path connectivity, priority, hysteresis, pins and opt-out")
    quit(0)
