extends SceneTree
## Run with a Cgame binary that has the built-in world_partition module:
## godot --headless --path misc/cgame_forest_showcase -s res://tests/smoke_streaming.gd
##
## Exercises resource sharing, cell instantiation, unload/reload, stable procedural
## placement and per-cell graphic quality settings using a real SceneTree.

const CELL_SCENE_PATH: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 360


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest streaming smoke FAILED: " + reason)
    quit(1)


func _wait_for_cell(stream: WorldPartition3D, cell: Vector2i,
        expected: bool) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell) == expected:
            return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(CELL_SCENE_PATH):
        _fail("cell scene is missing")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)

    var stream := WorldPartition3D.new()
    stream.name = "TestStream"
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 1
    stream.max_new_requests_per_frame = 1
    stream.max_instances_per_frame = 1
    stream.max_concurrent_requests = 2
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    stream.set_cell_scene(Vector2i(0, 0), CELL_SCENE_PATH)
    stream.set_cell_scene(Vector2i(-1, 0), CELL_SCENE_PATH)

    var origin := Vector2i(0, 0)
    if not await _wait_for_cell(stream, origin, true):
        _fail("origin cell did not load")
        return
    if stream.get_loaded_cell_count() != 1:
        _fail("unexpected initial loaded count")
        return

    var cell := stream.get_child(0) as Node3D
    if cell == null or not cell.has_node("WindGrass"):
        _fail("streamed cell did not generate its instances")
        return
    var grass := cell.get_node("WindGrass") as MultiMeshInstance3D
    if grass.multimesh.instance_count != 225:
        _fail("incorrect grass instance count")
        return
    var before: Transform3D = grass.multimesh.get_instance_transform(0)
    cell.call("set_high_quality", false)
    if grass.multimesh.visible_instance_count != 112:
        _fail("performance quality profile did not reduce grass density")
        return

    observer.position.x = 100.0
    if not await _wait_for_cell(stream, origin, false):
        _fail("distant cell did not unload")
        return

    observer.position.x = 0.0
    if not await _wait_for_cell(stream, origin, true):
        _fail("origin cell did not reload")
        return
    var reloaded := stream.get_child(0) as Node3D
    var next_grass := reloaded.get_node("WindGrass") as MultiMeshInstance3D
    if next_grass.multimesh.get_instance_transform(0) != before:
        _fail("foliage layout changed across stream unload/reload")
        return

    observer.position.x = -39.0
    var negative := Vector2i(-1, 0)
    if not await _wait_for_cell(stream, negative, true):
        _fail("negative X cell did not load")
        return

    print("Forest streaming smoke PASSED: deterministic shared-cell reload, negative coordinates, performance quality")
    quit(0)
