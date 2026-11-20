extends SceneTree
## Real async PackedScene streaming with a second gameplay source.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_sources.gd

const CELL_SCENE = "res://cells/forest_cell.tscn"
const MAX_FRAMES = 360


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Additional streaming sources smoke FAILED: " + reason)
    quit(1)


func _wait_for_cell(stream: WorldPartition3D, cell: Vector2i, loaded: bool) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell) == loaded:
            return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(CELL_SCENE):
        _fail("cell resource missing")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)
    var world := WorldPartition3D.new()
    world.name = "AdditionalSourcesTest"
    world.cell_size = 32.0
    world.load_radius = 0
    world.unload_radius = 0
    world.max_new_requests_per_frame = 1
    world.max_instances_per_frame = 1
    root.add_child(world)
    world.observer_path = world.get_path_to(observer)
    world.set_cell_scene(Vector2i(0, 0), CELL_SCENE)
    world.set_cell_scene(Vector2i(3, 0), CELL_SCENE)
    world.set_cell_scene(Vector2i(-3, 0), CELL_SCENE)

    if not await _wait_for_cell(world, Vector2i.ZERO, true):
        _fail("observer cell did not load")
        return
    if not world.set_streaming_source("quest", Vector3(96.0, 0.0, 0.0)):
        _fail("failed to register an objective source")
        return
    if not world.has_streaming_source("quest") or world.get_streaming_source_count() != 1:
        _fail("source registry did not retain its name")
        return
    if world.get_streaming_source_cell("quest") != Vector2i(3, 0):
        _fail("source position was not converted to the correct cell")
        return
    if not await _wait_for_cell(world, Vector2i(3, 0), true):
        _fail("remote quest cell was not loaded without moving observer")
        return
    if world.get_loaded_cell_count() != 2:
        _fail("single remote source should load only one additional registered cell")
        return

    if not world.set_streaming_source("quest", Vector3(-96.0, 0.0, 0.0)):
        _fail("existing source could not be moved")
        return
    if not await _wait_for_cell(world, Vector2i(-3, 0), true):
        _fail("updated source did not load the new target cell")
        return
    if not await _wait_for_cell(world, Vector2i(3, 0), false):
        _fail("obsolete quest cell stayed loaded after source moved")
        return
    if not world.is_cell_loaded(Vector2i.ZERO):
        _fail("source update disrupted high-priority observer cell")
        return

    world.remove_streaming_source("quest")
    if world.has_streaming_source("quest") or world.get_streaming_source_count() != 0:
        _fail("removing source left stale registry state")
        return
    if not await _wait_for_cell(world, Vector2i(-3, 0), false):
        _fail("remote quest cell stayed loaded after source removal")
        return

    world.set_streaming_source("test", Vector3(-96.0, 0.0, 0.0), 0)
    world.clear_streaming_sources()
    if world.get_streaming_source_count() != 0:
        _fail("clearing sources left registered entries")
        return

    print("Additional streaming sources smoke PASSED: remote cell loading, updates, unloading, observer priority and cleanup")
    quit(0)
