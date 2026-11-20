extends SceneTree
## Headless LOD regression: two loaded forest cells switch near/distant data
## without losing deterministic tree placement or reintroducing far colliders.
## Run with the compiled Cgame editor, from the repository root:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_lod.gd

const SCENE: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 360


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest distance LOD smoke FAILED: " + reason)
    quit(1)


func _wait_loaded(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell):
            return true
        await process_frame
    return false


func _find_cell(stream: WorldPartition3D, cell: Vector2i) -> Node3D:
    var origin: Vector3 = stream.cell_to_local_position(cell)
    for child in stream.get_children():
        var node := child as Node3D
        if node != null and not node.is_queued_for_deletion():
            if node.position.distance_to(origin) < 0.01:
                return node
    return null


func _run() -> void:
    if not ResourceLoader.exists(SCENE):
        _fail("forest scene resource is missing")
        return

    var observer := Node3D.new()
    observer.name = "LODObserver"
    root.add_child(observer)
    var stream := WorldPartition3D.new()
    stream.name = "LODStream"
    stream.cell_size = 32.0
    stream.load_radius = 1
    stream.unload_radius = 2
    stream.detail_radius = 0
    stream.max_detail_transitions_per_frame = 2
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    var home := Vector2i(0, 0)
    var eastern := Vector2i(1, 0)
    stream.set_cell_scene(home, SCENE)
    stream.set_cell_scene(eastern, SCENE)

    if not await _wait_loaded(stream, home) or not await _wait_loaded(stream, eastern):
        _fail("both cells must load")
        return
    var near := _find_cell(stream, home)
    var far := _find_cell(stream, eastern)
    if near == null or far == null:
        _fail("cell root instances are missing")
        return
    if stream.get_cell_detail_level(home) != 0 or stream.get_cell_detail_level(eastern) != 1:
        _fail("native initial detail tiers are incorrect")
        return
    if stream.get_distant_cell_count() != 1:
        _fail("expected one far detail cell")
        return
    if not near.has_node("WindGrass") or not near.has_node("FoliageCollisions"):
        _fail("near tier lost grass or colliders")
        return
    if far.has_node("WindGrass") or far.has_node("FoliageCollisions") or far.has_node("Stones"):
        _fail("distant tier allocated grass, collisions or rocks")
        return
    var far_trees := far.get_node_or_null("TreeTrunks") as MultiMeshInstance3D
    var near_trees := near.get_node_or_null("TreeTrunks") as MultiMeshInstance3D
    if far_trees == null or near_trees == null:
        _fail("tree silhouettes are missing")
        return
    if far_trees.multimesh.instance_count != 16 or near_trees.multimesh.instance_count <= 16:
        _fail("near and distant tree budgets are not distinct")
        return
    var expected_first: Transform3D = near_trees.multimesh.get_instance_transform(0)

    observer.position.x = 33.0
    stream.update_streaming()
    # The transition budget is 2 per streaming update.
    for i in range(3):
        await process_frame
    if stream.get_cell_detail_level(home) != 1 or stream.get_cell_detail_level(eastern) != 0:
        _fail("near/far tiers did not switch with the observer")
        return
    if near.has_node("WindGrass") or not far.has_node("WindGrass"):
        _fail("grass/colliders did not move between near and far cells")
        return
    far_trees = near.get_node_or_null("TreeTrunks") as MultiMeshInstance3D
    if far_trees == null or far_trees.multimesh.get_instance_transform(0) != expected_first:
        _fail("deterministic far instance placement changed across LOD transitions")
        return

    if not stream.pin_cell(home):
        _fail("pinning the far home hub failed")
        return
    stream.update_streaming()
    if stream.get_cell_detail_level(home) != 0 or not near.has_node("WindGrass"):
        _fail("pinned hub must restore full detail")
        return
    stream.unpin_cell(home)
    stream.detail_radius = -1
    stream.update_streaming()
    if stream.get_distant_cell_count() != 0 or not near.has_node("FoliageCollisions"):
        _fail("turning LOD off should restore every loaded cell to full detail")
        return
    if stream.get_cell_detail_level(Vector2i(-50, -50)) != -1:
        _fail("missing cell must have no detail level")
        return

    # Hysteresis: already-full cells stay detailed for one extra grid ring,
    # but genuinely distant cells only return to full detail in inner radius.
    stream.detail_radius = 0
    stream.detail_hysteresis_cells = 1
    observer.position.x = 0.0
    stream.update_streaming()
    if stream.get_cell_detail_level(home) != 0:
        _fail("home cell failed to enter full detail at the inner radius")
        return
    observer.position.x = 33.0
    stream.update_streaming()
    if stream.get_cell_detail_level(home) != 0:
        _fail("one-cell hysteresis did not preserve near detail")
        return
    observer.position.x = 65.0
    stream.update_streaming()
    if stream.get_cell_detail_level(home) != 1:
        _fail("home cell did not demote outside the hysteresis radius")
        return
    observer.position.x = 33.0
    stream.update_streaming()
    if stream.get_cell_detail_level(home) != 1:
        _fail("far cell promoted too early and will thrash at the boundary")
        return
    observer.position.x = 0.0
    stream.update_streaming()
    if stream.get_cell_detail_level(home) != 0:
        _fail("far cell did not promote on entering the inner radius")
        return

    print("Forest LOD smoke PASSED: deterministic near/far tiers, pins, disabling LOD, and boundary hysteresis")
    quit(0)
