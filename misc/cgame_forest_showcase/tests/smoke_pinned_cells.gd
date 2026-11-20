extends SceneTree
## Native WorldPartition3D manual residency pin integration.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_pinned_cells.gd
## Pins create a second streaming source without expanding the observer radius.

const SCENE_PATH: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 500


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Pinned-cell smoke FAILED: " + message)
    quit(1)


func _wait_cell(stream: WorldPartition3D, cell: Vector2i, loaded: bool) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell) == loaded:
            return true
        await process_frame
    return false


func _run() -> void:
    var observer := Node3D.new()
    observer.name = "PinnedCellObserver"
    root.add_child(observer)

    var stream := WorldPartition3D.new()
    stream.name = "PinnedCellWorld"
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    stream.max_instances_per_frame = 1
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)

    var origin := Vector2i.ZERO
    var remote := Vector2i(6, 6)
    stream.set_cell_scene(origin, SCENE_PATH)
    stream.set_cell_scene(remote, SCENE_PATH)

    if not stream.pin_cell(remote) or not stream.pin_cell(remote):
        _fail("idempotent registered cell pin failed")
        return
    if stream.get_pinned_cell_count() != 1 or not stream.is_cell_pinned(remote):
        _fail("duplicate cell pin inflated the count")
        return

    if not await _wait_cell(stream, origin, true):
        _fail("primary observer scene did not load")
        return
    if stream.is_cell_loaded(remote):
        _fail("remote pinned cell loaded before nearby player with budget one")
        return
    if not await _wait_cell(stream, remote, true):
        _fail("pinned remote location did not load asynchronously")
        return
    if stream.get_loaded_cell_count() != 2:
        _fail("primary plus pinned remote cell should both remain resident")
        return
    if stream.get_cell_node(remote) == null:
        _fail("pinned cell has no instantiated Node3D root")
        return

    stream.unpin_cell(remote)
    stream.update_streaming()
    if stream.is_cell_loaded(remote) or stream.get_pinned_cell_count() != 0:
        _fail("released remote pin was not unloaded outside the radius")
        return
    if stream.get_cell_scene(remote) != SCENE_PATH:
        _fail("unpin removed the scene registration")
        return

    # Pins survive temporarily disabling streaming but do not retain active
    # game nodes while disabled. They load again when streaming is enabled.
    if not stream.pin_cell(remote):
        _fail("remote cell could not be repinned")
        return
    stream.set_streaming_enabled(false)
    if stream.get_loaded_cell_count() != 0 or not stream.is_cell_pinned(remote):
        _fail("disabled streaming did not unload scenes while preserving pin")
        return
    stream.set_streaming_enabled(true)
    if not await _wait_cell(stream, remote, true):
        _fail("remote pin did not recover after enabling streaming")
        return

    stream.clear_pinned_cells()
    stream.update_streaming()
    if stream.get_pinned_cell_count() != 0 or stream.is_cell_loaded(remote):
        _fail("clearing residency pins did not release remote scene")
        return

    stream.pin_cell(remote)
    stream.remove_cell_scene(remote)
    if stream.is_cell_pinned(remote) or stream.get_pinned_cell_count() != 0:
        _fail("unregistering a cell did not clear its pin")
        return

    print("Pinned-cell smoke PASSED: remote loading, near-first priority, idempotency, unloading, disable/enable and registration cleanup")
    quit(0)
