extends SceneTree
## Headless regression for strict source priority and player-first work budgets.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_source_priorities.gd
##
## Three remote cells share one PackedScene and compete for ONE instance per
## frame. Even with a lower-sorting name, urgent sources must load first.

const CELL_SCENE: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 360


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Source priority smoke FAILED: " + message)
    quit(1)


func _run() -> void:
    if not ResourceLoader.exists(CELL_SCENE):
        _fail("forest cell PackedScene is missing")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)
    var world := WorldPartition3D.new()
    world.name = "PriorityWorld"
    world.cell_size = 32.0
    world.load_radius = 0
    world.unload_radius = 0
    world.max_instances_per_frame = 1
    world.max_new_requests_per_frame = 1
    world.max_concurrent_requests = 1
    root.add_child(world)
    world.observer_path = world.get_path_to(observer)
    world.set_cell_scene(Vector2i.ZERO, CELL_SCENE)
    world.set_cell_scene(Vector2i(3, 0), CELL_SCENE)
    world.set_cell_scene(Vector2i(-3, 0), CELL_SCENE)

    var order: Array[Vector2i] = []
    world.cell_loaded.connect(func(cell: Vector2i) -> void:
        order.append(cell)
    )
    # Alphabetical order would select "a_background" first. Priority must
    # override that order without displacing the observer's own cell.
    if not world.set_streaming_source("a_background", Vector3(96, 0, 0), 0, 0):
        _fail("background source was rejected")
        return
    if not world.set_streaming_source("z_urgent", Vector3(-96, 0, 0), 0, 3):
        _fail("urgent source was rejected")
        return
    if world.get_streaming_source_priority("a_background") != 0 or world.get_streaming_source_priority("z_urgent") != 3:
        _fail("native source priority getter differs from requested priority")
        return

    for i in range(MAX_FRAMES):
        if order.size() >= 3:
            break
        await process_frame
    if order.size() != 3:
        _fail("not all observer/urgent/background cells were instantiated")
        return
    if order[0] != Vector2i.ZERO:
        _fail("extra sources took the instance budget before the player")
        return
    if order[1] != Vector2i(-3, 0):
        _fail("urgent source did not receive first extra instantiation slot")
        return
    if order[2] != Vector2i(3, 0):
        _fail("background source did not load after urgent source")
        return

    if not world.set_streaming_source_priority("a_background", 2):
        _fail("priority cannot be updated at runtime")
        return
    if world.get_streaming_source_priority("a_background") != 2:
        _fail("priority update is not observable")
        return
    world.remove_streaming_source("a_background")
    world.remove_streaming_source("z_urgent")
    if world.get_streaming_source_count() != 0 or world.get_streaming_source_priority("z_urgent") != -1:
        _fail("removed sources retained priority metadata")
        return

    print("Source priority smoke PASSED: player-first instance budget, urgent-before-background, runtime change and cleanup")
    quit(0)
