extends SceneTree
## Native named streaming sources: priority, readiness events, overlap, unload.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_streaming_sources.gd
##
## Uses the real WorldPartition3D and streamed forest PackedScene, not mocks.

const SCENE_PATH: String = "res://cells/forest_cell.tscn"
const SURVEY: Vector2i = Vector2i(-5, 4)
const TOWER: Vector2i = Vector2i(3, -7)
const MAX_FRAMES: int = 900


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Multi-source streaming smoke FAILED: " + message)
    quit(1)


func _wait_cell(world: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if world.is_cell_loaded(cell):
            return true
        await process_frame
    return false


func _wait_source(world: WorldPartition3D, name: String) -> bool:
    for i in range(MAX_FRAMES):
        if world.is_streaming_source_ready(name):
            return true
        await process_frame
    return false


func _run() -> void:
    var observer := Node3D.new()
    observer.name = "MultiSourceObserver"
    root.add_child(observer)

    var world := WorldPartition3D.new()
    world.cell_size = 32.0
    world.load_radius = 0
    world.unload_radius = 0
    world.max_instances_per_frame = 1
    root.add_child(world)
    world.observer_path = world.get_path_to(observer)
    world.set_cell_scene(Vector2i.ZERO, SCENE_PATH)
    world.set_cell_scene(TOWER, SCENE_PATH)
    for z in range(SURVEY.y - 1, SURVEY.y + 2):
        for x in range(SURVEY.x - 1, SURVEY.x + 2):
            world.set_cell_scene(Vector2i(x, z), SCENE_PATH)

    var ready_names: Array[String] = []
    var unready_names: Array[String] = []
    world.streaming_source_ready.connect(func(name: String) -> void:
        ready_names.append(name))
    world.streaming_source_unready.connect(func(name: String) -> void:
        unready_names.append(name))

    # Two independent remote streaming sources with unequal radii/priority.
    if not world.set_streaming_source("survey", SURVEY, 1, 2, 80):
        _fail("failed to register high-priority survey source")
        return
    if not world.set_streaming_source("watchtower", TOWER, 0, 1, 25):
        _fail("failed to register low-priority watchtower source")
        return
    var source_info: Dictionary = world.get_streaming_source("survey")
    if source_info.get("priority") != 80 or source_info.get("load_radius") != 1 \
            or source_info.get("unload_radius") != 2 or world.get_streaming_source_count() != 2:
        _fail("source metadata differs from configured priorities and radii")
        return

    if not await _wait_cell(world, Vector2i.ZERO):
        _fail("primary player cell failed to load")
        return
    if world.is_cell_loaded(TOWER):
        _fail("remote watchtower loaded before nearer higher-priority cells")
        return

    if not await _wait_source(world, "survey"):
        _fail("high-priority 3x3 survey region failed to become ready")
        return
    if world.is_streaming_source_ready("watchtower"):
        _fail("lower-priority watchtower became ready before survey region")
        return
    if absf(world.get_streaming_source_progress("survey") - 1.0) > 0.00001:
        _fail("fully instantiated survey area did not reach 100 percent")
        return
    if world.get_streaming_source_progress("watchtower") != 0.0:
        _fail("low-priority watchtower progress advanced ahead of the survey")
        return
    if world.get_loaded_cell_count() != 10:
        _fail("player plus nine survey cells should be resident before watchtower")
        return
    if not await _wait_source(world, "watchtower"):
        _fail("secondary watchtower source failed to become ready")
        return
    if world.get_streaming_source_progress("watchtower") != 1.0:
        _fail("completed one-cell source did not report 100 percent")
        return
    if not ready_names.has("survey") or not ready_names.has("watchtower"):
        _fail("named source readiness signals were not emitted")
        return

    # A second source overlapping a loaded cell must not create duplicate
    # scene roots. Removing one source should retain the overlapping cell.
    var before_count: int = world.get_loaded_cell_count()
    if not world.set_streaming_source("watchtower_backup", TOWER, 0, 0, 10):
        _fail("overlapping backup source could not be registered")
        return
    world.update_streaming()
    if world.get_loaded_cell_count() != before_count:
        _fail("overlapping sources instantiated a duplicate remote cell")
        return
    world.remove_streaming_source("watchtower")
    world.update_streaming()
    if not world.is_cell_loaded(TOWER):
        _fail("shared remote cell unloaded while backup source still wanted it")
        return

    world.remove_streaming_source("watchtower_backup")
    world.update_streaming()
    if world.is_cell_loaded(TOWER):
        _fail("remote cell did not unload when its final source was removed")
        return

    # The survey is independent of the player's original loading radius.
    world.remove_streaming_source("survey")
    world.update_streaming()
    if world.get_streaming_source_count() != 0 or world.get_loaded_cell_count() != 1:
        _fail("removed remote regions remained loaded without a streaming source")
        return
    if not unready_names.has("survey") or not unready_names.has("watchtower"):
        _fail("source-loss signals did not report removed ready sources")
        return

    print("Multi-source streaming smoke PASSED: two independent regions, priorities, readiness signals, overlap and unload")
    quit(0)
