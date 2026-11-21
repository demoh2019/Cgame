extends SceneTree
## Run with a compiled Cgame binary:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_navigation_clearance.gd
## Validate native triangle-vs-disc clearance, slope filtering, tile seams,
## and the actual generated tree/rock footprints in the streamed scene.

const ForestNavigationMesh = preload("res://scripts/forest_navigation_mesh.gd")
const FOREST_SCENE: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 400


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest navigation clearance smoke FAILED: " + reason)
    quit(1)


func _run() -> void:
    var observer := Node3D.new()
    observer.position = Vector3(8.0, 1.0, 8.0)
    root.add_child(observer)

    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    stream.detail_radius = 0
    stream.navigation_radius = 0
    stream.max_instances_per_frame = 1
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    stream.set_cell_scene(Vector2i.ZERO, FOREST_SCENE)

    # Native builder must accept exactly (resolution + 1)^2 sampled vertices.
    var flat := PackedVector3Array()
    var sloped := PackedVector3Array()
    for z in range(5):
        for x in range(5):
            flat.append(Vector3(x, 0.0, z))
            sloped.append(Vector3(x, float(x) * 0.7, z))

    var empty_blockers := PackedVector3Array()
    var complete: NavigationMesh = stream.build_navigation_tile(flat, 4, empty_blockers, 0.0, 45.0)
    if complete == null or complete.get_polygon_count() != 32:
        _fail("flat 4x4 mesh should contain exactly 32 navigable triangles")
        return

    var blockers := PackedVector3Array([Vector3(2.0, 2.0, 0.1)])
    var narrow: NavigationMesh = stream.build_navigation_tile(flat, 4, blockers, 0.0, 45.0)
    var wide: NavigationMesh = stream.build_navigation_tile(flat, 4, blockers, 1.1, 45.0)
    if (narrow == null or wide == null or narrow.get_polygon_count() >= 32
            or wide.get_polygon_count() >= narrow.get_polygon_count()
            or wide.get_polygon_count() <= 0):
        _fail("agent-radius expansion did not conservatively remove obstructed triangles")
        return

    var reject_slope: NavigationMesh = stream.build_navigation_tile(
        sloped, 4, empty_blockers, 0.45, 20.0)
    var accept_slope: NavigationMesh = stream.build_navigation_tile(
        sloped, 4, empty_blockers, 0.45, 45.0)
    if (reject_slope == null or accept_slope == null
            or reject_slope.get_polygon_count() != 0
            or accept_slope.get_polygon_count() != 32):
        _fail("native slope threshold did not distinguish steep and walkable surfaces")
        return

    # Tiles sample the same global terrain function; boundary coordinates
    # must coincide to avoid NavigationRegion3D seams.
    var left: PackedVector3Array = ForestNavigationMesh.sample_vertices(Vector3.ZERO)
    var right: PackedVector3Array = ForestNavigationMesh.sample_vertices(Vector3(32, 0, 0))
    var resolution: int = ForestNavigationMesh.SAMPLE_COUNT
    for z in range(resolution + 1):
        var a: Vector3 = left[z * (resolution + 1) + resolution]
        var b: Vector3 = right[z * (resolution + 1)]
        if (a - b - Vector3(32, 0, 0)).length() > 0.0001:
            _fail("adjacent terrain tiles do not share identical world seam vertices")
            return

    for frame in range(MAX_FRAMES):
        if stream.is_cell_navigation_ready(Vector2i.ZERO):
            break
        await process_frame
    if not stream.is_cell_navigation_ready(Vector2i.ZERO):
        _fail("live forest navigation did not become ready")
        return

    var cell_root: Node3D = stream.get_cell_instance(Vector2i.ZERO)
    if cell_root == null:
        _fail("the live forest cell was lost")
        return
    var obstacle_bodies: StaticBody3D = cell_root.get_node_or_null("FoliageCollisions") as StaticBody3D
    var nav_region: NavigationRegion3D = cell_root.get_node_or_null(
        "StreamingNavigationRegion") as NavigationRegion3D
    if obstacle_bodies == null or nav_region == null or nav_region.navigation_mesh == null:
        _fail("real scene did not create both obstacles and a native navmesh tile")
        return
    var footprints: PackedVector3Array = cell_root.get("navigation_blockers")
    if footprints.size() < 5 or footprints.size() != obstacle_bodies.get_child_count():
        _fail("navigation footprints do not correspond to generated tree and rock colliders")
        return
    var vertices: PackedVector3Array = ForestNavigationMesh.sample_vertices(
        cell_root.global_position)
    var uncarved: NavigationMesh = stream.build_navigation_tile(
        vertices, resolution, PackedVector3Array(), 0.45, 42.0)
    if uncarved == null:
        _fail("native uncarved comparison tile was rejected")
        return
    var carved_count: int = nav_region.navigation_mesh.get_polygon_count()
    if carved_count <= 0 or carved_count >= uncarved.get_polygon_count():
        _fail("the real forest NavMesh did not remove tree/rock clearance triangles")
        return

    print("Forest navigation clearance smoke PASSED: native slope, collision clearance, agent radius, shared tile edges, game foliage footprints")
    quit(0)
