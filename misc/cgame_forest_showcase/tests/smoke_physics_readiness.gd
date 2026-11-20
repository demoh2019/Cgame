extends SceneTree
## WorldPartition3D scene-tree versus physics-tick activation regression.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics_readiness.gd
##
## The engine emits one physics-ready transition after its two-tick barrier.
## Unloading revokes it, and reloading requires a fresh barrier.

const CELL: Vector2i = Vector2i.ZERO
const SCENE_PATH: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 600


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Physics readiness smoke FAILED: " + reason)
    quit(1)


func _wait_ready(stream: WorldPartition3D) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_physics_ready(CELL):
            return true
        await physics_frame
    return false


func _run() -> void:
    var observer := Node3D.new()
    observer.name = "PhysicsReadyObserver"
    root.add_child(observer)

    var stream := WorldPartition3D.new()
    stream.name = "PhysicsReadyStreamer"
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    var ready_events: Array[Vector2i] = []
    var unready_events: Array[Vector2i] = []
    stream.cell_physics_ready.connect(func(cell: Vector2i) -> void:
        ready_events.append(cell))
    stream.cell_physics_unready.connect(func(cell: Vector2i) -> void:
        unready_events.append(cell))
    stream.set_cell_scene(CELL, SCENE_PATH)

    if not await _wait_ready(stream):
        _fail("native physics readiness never became true")
        return
    if not stream.is_cell_loaded(CELL) or not stream.are_cells_physics_ready(CELL):
        _fail("scene and physics readiness disagreed")
        return
    if stream.get_physics_ready_cell_count() != 1:
        _fail("physics-ready cell count differs from active region")
        return
    if ready_events.size() != 1 or ready_events[0] != CELL:
        _fail("expected exactly one physics-ready transition")
        return
    if stream.are_cells_physics_ready(CELL, 1):
        _fail("unregistered neighbor cells cannot be declared physics ready")
        return

    var region: Node3D = stream.get_cell_node(CELL)
    if region == null or region.get_node_or_null("TerrainPatch/GroundCollision") == null:
        _fail("ready cell lacks the actual terrain collision body")
        return

    for i in range(5):
        await physics_frame
    if ready_events.size() != 1:
        _fail("physics-ready event repeated for the same instance")
        return

    observer.position.x = 96.0
    stream.update_streaming()
    if stream.is_cell_loaded(CELL) or stream.is_cell_physics_ready(CELL):
        _fail("unloaded cell retained physics readiness")
        return
    if unready_events.size() != 1 or unready_events[0] != CELL:
        _fail("unload did not emit one physics-unready signal")
        return

    observer.position.x = 0.0
    stream.update_streaming()
    if not await _wait_ready(stream):
        _fail("reloaded cell did not pass a fresh physics barrier")
        return
    if ready_events.size() != 2:
        _fail("reload did not emit a second physics-ready event")
        return

    stream.set_streaming_enabled(false)
    if stream.get_physics_ready_cell_count() != 0 \
            or stream.is_cell_physics_ready(CELL):
        _fail("disabled streaming retained physics-ready cells")
        return
    if unready_events.size() != 2:
        _fail("disabling streaming did not revoke physics readiness")
        return

    print("Physics readiness smoke PASSED: two-stage scene/physics lifecycle, events, reload and disabled streaming")
    quit(0)
