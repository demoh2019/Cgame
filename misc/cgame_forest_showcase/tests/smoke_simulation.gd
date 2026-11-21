extends SceneTree
## Native cell-simulation lifecycle regression with real streamed forest scenes.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_simulation.gd

const FOREST: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 360


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Forest simulation smoke FAILED: " + message)
    quit(1)


func _wait_loaded(world: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if world.get_cell_instance(cell) != null:
            return true
        await process_frame
    return false


func _wait_active(world: WorldPartition3D, cell: Vector2i, active: bool) -> bool:
    for i in range(MAX_FRAMES):
        world.update_streaming()
        if world.is_cell_simulation_active(cell) == active:
            var scene := world.get_cell_instance(cell)
            if scene != null and scene.get("streaming_simulation_active") == active:
                return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(FOREST):
        _fail("forest PackedScene is missing")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)
    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 2
    stream.unload_radius = 3
    stream.detail_radius = 1
    stream.simulation_radius = 0
    stream.simulation_hysteresis_cells = 1
    stream.max_simulation_transitions_per_frame = 1
    stream.max_new_requests_per_frame = 2
    stream.max_instances_per_frame = 1
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)

    for x in range(3):
        stream.set_cell_scene(Vector2i(x, 0), FOREST)
    for x in range(3):
        if not await _wait_loaded(stream, Vector2i(x, 0)):
            _fail("configured test forest cell did not instantiate")
            return

    var home := Vector2i(0, 0)
    var adjacent := Vector2i(1, 0)
    var distant := Vector2i(2, 0)
    if not stream.is_cell_simulation_active(home):
        _fail("observer's current cell was not simulation-active initially")
        return
    if stream.is_cell_simulation_active(adjacent) or stream.is_cell_simulation_active(distant):
        _fail("distant cells started simulation-active before entering inner radius")
        return
    if stream.get_simulation_active_cell_count() != 1:
        _fail("expected exactly one simulation-active cell at start")
        return

    # All three geometry scenes remain instantiated independent of simulation.
    var distant_scene := stream.get_cell_instance(distant)
    if distant_scene == null or distant_scene.get_child_count() == 0:
        _fail("dormant remote scene lost its graphical children")
        return

    observer.position.x = 33.0
    if not await _wait_active(stream, adjacent, true):
        _fail("moving into a neighboring cell did not activate its simulation")
        return
    if not stream.is_cell_simulation_active(home):
        _fail("simulation hysteresis did not retain the previous cell")
        return

    observer.position.x = 65.0
    if not await _wait_active(stream, distant, true):
        _fail("new observer cell did not activate")
        return
    if not await _wait_active(stream, home, false):
        _fail("previous cell did not become inactive outside hysteresis")
        return
    if not stream.is_cell_loaded(home):
        _fail("simulation deactivation incorrectly unloaded geometry")
        return

    # The visual LOD toggle is independent of simulation processing.
    stream.detail_radius = -1
    stream.update_streaming()
    if stream.is_cell_simulation_active(home):
        _fail("disabling visual LOD re-enabled distant simulation")
        return

    if not stream.pin_cell(home):
        _fail("could not pin remote gameplay hub")
        return
    if not await _wait_active(stream, home, true):
        _fail("pinned hub did not restore full gameplay simulation")
        return
    stream.unpin_cell(home)
    if not await _wait_active(stream, home, false):
        _fail("removing hub pin did not restore distance-based simulation")
        return

    stream.simulation_radius = -1
    for x in range(3):
        if not await _wait_active(stream, Vector2i(x, 0), true):
            _fail("opt-out simulation radius did not reactivate all loaded cells")
            return
    if stream.get_simulation_active_cell_count() != 3:
        _fail("enabled simulation count is not consistent with live scene roots")
        return

    print("Forest simulation smoke PASSED: near-only activity, callback, hysteresis, budgets, pins, LOD independence, disable")
    quit(0)
