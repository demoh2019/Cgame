extends SceneTree
## Run with a built Cgame binary:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_activation_fence.gd
##
## Uses real asynchronous PackedScene streaming, not mocked completion.
## Scene roots must pass both the physics-frame delay and an opt-in callback.

const PROBE_SCENE: String = "res://tests/activation_probe.tscn"
const TEST_FRAMES: int = 420
const SOURCE: String = "arrival"


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest activation fence smoke FAILED: " + reason)
    quit(1)


func _wait_cell(world: WorldPartition3D, cell: Vector2i) -> Node3D:
    for i in range(TEST_FRAMES):
        var scene: Node3D = world.get_cell_instance(cell)
        if scene != null:
            return scene
        await process_frame
    return null


func _run() -> void:
    if not ResourceLoader.exists(PROBE_SCENE):
        _fail("activation PackedScene missing")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)
    var world := WorldPartition3D.new()
    world.cell_size = 32.0
    world.load_radius = 0
    world.unload_radius = 0
    world.max_new_requests_per_frame = 1
    world.max_instances_per_frame = 1
    world.min_physics_frames_after_load = 4
    root.add_child(world)
    world.observer_path = world.get_path_to(observer)
    world.set_cell_scene(Vector2i.ZERO, PROBE_SCENE)
    world.set_cell_scene(Vector2i(3, 0), PROBE_SCENE)
    world.set_cell_scene(Vector2i(-3, 0), PROBE_SCENE)

    var home: Node3D = await _wait_cell(world, Vector2i.ZERO)
    if home == null:
        _fail("observer cell did not load")
        return
    if world.is_cell_activation_ready(Vector2i(999, 999)):
        _fail("missing cell was incorrectly marked activation ready")
        return

    if not world.set_streaming_source(SOURCE, Vector3(96.0, 0, 0), 0, 3):
        _fail("could not register urgent activation test source")
        return
    var scene: Node3D = await _wait_cell(world, Vector2i(3, 0))
    if scene == null:
        _fail("remote source did not instantiate")
        return
    if not world.is_streaming_source_ready(SOURCE):
        _fail("source scene roots not marked loaded")
        return
    if world.is_cell_activation_ready(Vector2i(3, 0)):
        _fail("new root bypassed physics-frame/scene activation fence")
        return
    if world.get_streaming_source_activation_progress(SOURCE) != 0.0:
        _fail("activation progress advanced before the gate opened")
        return

    # Allow callback immediately: physics frame threshold still blocks it.
    scene.set("allow_activation", true)
    if world.is_streaming_source_activation_ready(SOURCE):
        _fail("scene callback bypassed physics stabilization delay")
        return
    for i in range(6):
        await physics_frame
    await process_frame
    if not world.is_cell_activation_ready(Vector2i(3, 0)):
        _fail("physics-frame stabilization did not complete")
        return
    if (world.get_streaming_source_activated_cell_count(SOURCE) != 1
            or not is_equal_approx(world.get_streaming_source_activation_progress(SOURCE), 1.0)):
        _fail("activation progress and count were not updated")
        return

    # Per-root callback revokes readiness without unloading the scene.
    scene.set("allow_activation", false)
    if world.is_streaming_source_activation_ready(SOURCE):
        _fail("scene-defined readiness gate was ignored")
        return
    if not world.is_cell_loaded(Vector2i(3, 0)):
        _fail("readiness revocation unloaded graphics")
        return
    scene.set("allow_activation", true)

    # Moving the source invalidates its readiness until a different scene
    # has loaded and passed BOTH conditions.
    if not world.set_streaming_source(SOURCE, Vector3(-96.0, 0, 0), 0, 3):
        _fail("failed to relocate source")
        return
    if world.is_streaming_source_activation_ready(SOURCE):
        _fail("moving source retained previous destination readiness")
        return
    var other: Node3D = await _wait_cell(world, Vector2i(-3, 0))
    if other == null:
        _fail("retargeted cell did not load")
        return
    for i in range(6):
        await physics_frame
    await process_frame
    if world.is_streaming_source_activation_ready(SOURCE):
        _fail("a false callback incorrectly accepted as activation ready")
        return
    other.set("allow_activation", true)
    if not world.is_streaming_source_activation_ready(SOURCE):
        _fail("new cell never became activation ready")
        return

    world.remove_streaming_source(SOURCE)
    if (world.is_streaming_source_activation_ready(SOURCE)
            or world.get_streaming_source_activation_progress(SOURCE) != 0.0):
        _fail("removed source retained activation state")
        return

    print("Forest activation fence smoke PASSED: physics frames, scene callback, progress, source retarget and cleanup")
    quit(0)
