extends SceneTree
## Run with compiled Cgame:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_cell_route_cache.gd
## Tests actual WorldPartition3D route cache with live forest scene loading.

const FOREST: String = "res://cells/forest_cell.tscn"
const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const START: Vector3 = Vector3(8, 1, 8)
const GOAL: Vector3 = Vector3(40, 1, 8)


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest cell route cache smoke FAILED: " + reason)
    quit(1)


func _wait_for_cell(stream: WorldPartition3D, cell: Vector2i, loaded: bool) -> bool:
    for frame in range(360):
        stream.update_streaming()
        if (stream.get_cell_instance(cell) != null) == loaded:
            return true
        await process_frame
    return false


func _run() -> void:
    var observer := Node3D.new()
    root.add_child(observer)
    observer.global_position = START
    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 1
    stream.unload_radius = 2
    stream.max_instances_per_frame = 2
    stream.max_cell_path_cache_entries = 4
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    stream.set_cell_scene(Vector2i(0, 0), FOREST)
    stream.set_cell_scene(Vector2i(1, 0), FOREST)

    var route: Array = QuestNavigation.cell_route(stream, START, GOAL)
    if route.size() != 2 or stream.get_cell_path_cache_miss_count() != 1:
        _fail("first quest route did not use native cache miss or correct two-cell path")
        return
    route[1] = Vector2i(99, 99)
    route = QuestNavigation.cell_route(stream, START, GOAL)
    if route.size() != 2 or route[1] != Vector2i(1, 0):
        _fail("script mutated the native cached route through the returned Array")
        return
    if stream.get_cell_path_cache_hit_count() != 1:
        _fail("repeated quest HUD query should hit the native route cache")
        return

    # Cache a negative live-only route before any PackedScene is instantiated.
    if not QuestNavigation.cell_route(stream, START, GOAL, true).is_empty():
        _fail("unloaded forest route unexpectedly passed live-only restriction")
        return
    if stream.get_cell_path_cache_entry_count() != 2:
        _fail("registered and live-only paths must occupy independent cache keys")
        return
    if not await _wait_for_cell(stream, Vector2i(0, 0), true):
        _fail("home forest cell did not finish streaming")
        return
    if not await _wait_for_cell(stream, Vector2i(1, 0), true):
        _fail("neighbor forest cell did not finish streaming")
        return
    # Live-cell changes must discard the negative live-only cache, but
    # preserve the configured topology route.
    var hits_before: int = stream.get_cell_path_cache_hit_count()
    if QuestNavigation.cell_route(stream, START, GOAL).size() != 2:
        _fail("registered topology route changed after scene instantiation")
        return
    if stream.get_cell_path_cache_hit_count() != hits_before + 1:
        _fail("a scene load unnecessarily invalidated registered quest routes")
        return
    if QuestNavigation.cell_route(stream, START, GOAL, true).size() != 2:
        _fail("live-only route did not refresh after both streamed scenes loaded")
        return
    if stream.get_cell_path_cache_entry_count() != 2:
        _fail("live-only route was not restored beside the registered cache entry")
        return

    observer.global_position = Vector3(500, 1, 8)
    if not await _wait_for_cell(stream, Vector2i(1, 0), false):
        _fail("remote forest scene was not unloaded after observer moved")
        return
    hits_before = stream.get_cell_path_cache_hit_count()
    if QuestNavigation.cell_route(stream, START, GOAL).size() != 2:
        _fail("registered route disappeared when a scene root unloaded")
        return
    if stream.get_cell_path_cache_hit_count() != hits_before + 1:
        _fail("unloading a scene incorrectly flushed the configured route cache")
        return
    if not QuestNavigation.cell_route(stream, START, GOAL, true).is_empty():
        _fail("loaded-only cached route remained valid across scene unload")
        return

    # A registered graph change must invalidate positive and negative paths.
    stream.remove_cell_scene(Vector2i(1, 0))
    if stream.get_cell_path_cache_entry_count() != 0:
        _fail("scene registration change failed to invalidate route cache")
        return
    if not QuestNavigation.cell_route(stream, START, GOAL).is_empty():
        _fail("removed scene registration still appeared reachable")
        return
    stream.set_cell_scene(Vector2i(1, 0), FOREST)
    if QuestNavigation.cell_route(stream, START, GOAL).size() != 2:
        _fail("re-registered quest destination did not restore path")
        return

    # Explicit reset and disabled caching keep the API usable.
    stream.clear_cell_path_cache()
    if (stream.get_cell_path_cache_entry_count() != 0
            or stream.get_cell_path_cache_hit_count() != 0
            or stream.get_cell_path_cache_miss_count() != 0):
        _fail("explicit cache reset did not clear entries and counters")
        return
    stream.max_cell_path_cache_entries = 0
    QuestNavigation.cell_route(stream, START, GOAL)
    QuestNavigation.cell_route(stream, START, GOAL)
    if stream.get_cell_path_cache_entry_count() != 0             or stream.get_cell_path_cache_miss_count() != 2:
        _fail("disabled cache unexpectedly stored a route")
        return

    print("Forest cell route cache smoke PASSED: quest cache, defensive copies, live-only invalidation, scene churn, graph edit and disabled mode")
    quit(0)
