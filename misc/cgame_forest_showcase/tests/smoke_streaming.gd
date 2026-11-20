extends SceneTree
## Run with a Cgame binary that has the built-in world_partition module:
## godot --headless --path misc/cgame_forest_showcase -s res://tests/smoke_streaming.gd
##
## Exercises resource sharing, cell instantiation, unload/reload, stable procedural
## placement and per-cell graphic quality settings using a real SceneTree.

const CELL_SCENE_PATH: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 360

var observed_cell_events: int = 0
var last_observed_cell: Vector2i = Vector2i.ZERO


func _on_observer_cell_changed(cell: Vector2i) -> void:
    observed_cell_events += 1
    last_observed_cell = cell


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


func _get_active_cell_node(stream: WorldPartition3D, grid_cell: Vector2i) -> Node3D:
    var expected: Vector3 = stream.cell_to_local_position(grid_cell)
    for child in stream.get_children():
        var node := child as Node3D
        if node != null and not node.is_queued_for_deletion():
            if node.position.distance_to(expected) < 0.01:
                return node
    return null


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
    stream.observer_cell_changed.connect(_on_observer_cell_changed)
    stream.set_cell_scene(Vector2i(0, 0), CELL_SCENE_PATH)
    stream.set_cell_scene(Vector2i(-1, 0), CELL_SCENE_PATH)

    var origin := Vector2i(0, 0)
    if not await _wait_for_cell(stream, origin, true):
        _fail("origin cell did not load")
        return
    if stream.get_loaded_cell_count() != 1:
        _fail("unexpected initial loaded count")
        return
    if not stream.has_observer_cell() or stream.get_observer_cell() != origin:
        _fail("native observer cell did not initialize")
        return
    if observed_cell_events < 1 or last_observed_cell != origin:
        _fail("observer_cell_changed did not emit for the first cell")
        return

    var cell := _get_active_cell_node(stream, origin)
    if cell == null or not cell.has_node("WindGrass"):
        _fail("streamed cell did not generate its instances")
        return
    var patch := cell.get_node_or_null("TerrainPatch") as Node3D
    if patch == null:
        _fail("streamed cell has no terrain patch")
        return
    var ground := patch.get_node_or_null("GroundMesh") as MeshInstance3D
    var terrain_body := patch.get_node_or_null("GroundCollision") as StaticBody3D
    var shape_node := patch.get_node_or_null("GroundCollision/HeightmapCollision") as CollisionShape3D
    if ground == null or terrain_body == null or shape_node == null:
        _fail("streamed terrain has no mesh or collision")
        return
    var height_shape := shape_node.shape as HeightMapShape3D
    if height_shape == null or height_shape.map_width != 33 or height_shape.map_depth != 33:
        _fail("terrain heightmap has unexpected shape or dimensions")
        return
    if shape_node.position.distance_to(Vector3(16, 0, 16)) > 0.001:
        _fail("terrain heightmap collision is not centered within its 32m tile")
        return
    var origin_arrays: Array = ground.mesh.surface_get_arrays(0)
    var origin_vertices: PackedVector3Array = origin_arrays[Mesh.ARRAY_VERTEX]
    var origin_normals: PackedVector3Array = origin_arrays[Mesh.ARRAY_NORMAL]
    if origin_vertices.size() != 1089:
        _fail("terrain patch should contain 33 x 33 vertices")
        return

    var obstacles := cell.get_node_or_null("FoliageCollisions") as StaticBody3D
    if obstacles == null or obstacles.get_child_count() < 9:
        _fail("streamed cell has no obstacle colliders")
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
    var reloaded := _get_active_cell_node(stream, origin)
    if reloaded == null or not reloaded.has_node("WindGrass"):
        _fail("reloaded cell root was not instantiated")
        return
    var next_grass := reloaded.get_node("WindGrass") as MultiMeshInstance3D
    if next_grass.multimesh.get_instance_transform(0) != before:
        _fail("foliage layout changed across stream unload/reload")
        return

    observer.position.x = -25.0
    var negative := Vector2i(-1, 0)
    # -25.0 belongs to cell -1 with a 32m cell width and has a registered scene.
    if not await _wait_for_cell(stream, negative, true):
        _fail("negative X cell did not load")
        return
    if stream.get_observer_cell() != negative or last_observed_cell != negative:
        _fail("observer_cell_changed did not track negative coordinates")
        return

    var negative_root := _get_active_cell_node(stream, negative)
    if negative_root == null:
        _fail("neighbor tile was not instantiated")
        return
    var other_ground := negative_root.get_node_or_null("TerrainPatch/GroundMesh") as MeshInstance3D
    if other_ground == null:
        _fail("negative tile lacks a terrain mesh")
        return
    var negative_arrays: Array = other_ground.mesh.surface_get_arrays(0)
    var negative_vertices: PackedVector3Array = negative_arrays[Mesh.ARRAY_VERTEX]
    var negative_normals: PackedVector3Array = negative_arrays[Mesh.ARRAY_NORMAL]
    # X=0 in the origin cell matches X=32 in the adjacent negative-X cell.
    # Both the height and the analytic normals must match to avoid visible seams.
    for z in [0, 1, 7, 16, 24, 31, 32]:
        var near_index: int = int(z) * 33
        var far_index: int = int(z) * 33 + 32
        if absf(origin_vertices[near_index].y - negative_vertices[far_index].y) > 0.0001:
            _fail("neighboring terrain tiles disagree on seam heights at Z=%d" % z)
            return
        if origin_normals[near_index].distance_to(negative_normals[far_index]) > 0.0001:
            _fail("neighboring terrain tiles disagree on seam normals at Z=%d" % z)
            return

    observer.position.x = -39.0
    # Cell -2 has no registered scene. Grid tracking must still report -2.
    # Explicitly advance streaming: process_frame fires before the Node process callback.
    stream.update_streaming()
    if stream.get_observer_cell() != Vector2i(-2, 0) or last_observed_cell != Vector2i(-2, 0):
        _fail("observer transition into an unregistered cell was not reported")
        return
    if observed_cell_events < 5:
        _fail("observer transitions were not signaled reliably")
        return

    print("Forest streaming smoke PASSED: deterministic terrain seams, heightmap colliders, reload, observer signals and quality")
    quit(0)
