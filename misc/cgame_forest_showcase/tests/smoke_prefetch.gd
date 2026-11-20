extends SceneTree
## End-to-end directional prefetch contract:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_prefetch.gd
##
## Tests priority, 2-cell forward corridor, turn cancellation, zero-disable,
## and retained origin when a directional region is unloaded.
## Requires the native WorldPartition3D provided by the Cgame fork.

const CELL_SCENE: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 400


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Directional prefetch smoke FAILED: " + message)
    quit(1)


func _wait_cell(stream: WorldPartition3D, cell: Vector2i, desired: bool) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell) == desired:
            return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(CELL_SCENE):
        _fail("streamed forest scene not present")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)

    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    stream.max_instances_per_frame = 1
    stream.prefetch_direction = Vector2i(1, 0)
    stream.prefetch_distance = 2
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)

    for x in range(-2, 3):
        stream.set_cell_scene(Vector2i(x, 0), CELL_SCENE)

    var origin := Vector2i.ZERO
    if not await _wait_cell(stream, origin, true):
        _fail("primary observer cell did not load")
        return
    if stream.is_cell_loaded(Vector2i(1, 0)):
        _fail("forward cell loaded before primary observer despite frame budget 1")
        return

    if not await _wait_cell(stream, Vector2i(2, 0), true):
        _fail("two-cell forward corridor was not prefetched")
        return
    if not stream.is_cell_loaded(Vector2i(1, 0)):
        _fail("prefetch corridor has a gap")
        return
    if stream.get_loaded_cell_count() != 3:
        _fail("extra cells beyond prefetch corridor were loaded")
        return

    stream.prefetch_direction = Vector2i(-1, 0)
    stream.update_streaming()
    if not stream.is_cell_loaded(origin):
        _fail("primary cell was discarded when direction reversed")
        return
    if stream.is_cell_loaded(Vector2i(1, 0)) or stream.is_cell_loaded(Vector2i(2, 0)):
        _fail("outdated forward corridor was not unloaded on turning")
        return
    if not await _wait_cell(stream, Vector2i(-2, 0), true):
        _fail("reverse direction did not prefetch two cells")
        return
    if not stream.is_cell_loaded(Vector2i(-1, 0)):
        _fail("reverse prefetch corridor has a gap")
        return

    stream.prefetch_distance = 0
    stream.update_streaming()
    if stream.get_loaded_cell_count() != 1 or not stream.is_cell_loaded(origin):
        _fail("zero distance did not deactivate forward prefetch")
        return

    stream.prefetch_distance = 2
    stream.prefetch_direction = Vector2i.ZERO
    stream.update_streaming()
    if stream.get_loaded_cell_count() != 1:
        _fail("zero direction unexpectedly prefetched cells")
        return

    print("Directional prefetch smoke PASSED: primary priority, forward corridor, reverse, unloading and disabled modes")
    quit(0)
