extends SceneTree
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_incremental_navmesh.gd
## Incremental triangle patches must produce exactly the same polygons as a
## full C++ rebuild, while re-testing only geometry near changed blockers.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const ForestNavigationMesh = preload("res://scripts/forest_navigation_mesh.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Incremental NavMesh smoke FAILED: " + reason)
    quit(1)


func _mesh_equals(a: NavigationMesh, b: NavigationMesh) -> bool:
    if a == null or b == null or a.vertices != b.vertices:
        return false
    if a.get_polygon_count() != b.get_polygon_count():
        return false
    for i in range(a.get_polygon_count()):
        if a.get_polygon(i) != b.get_polygon(i):
            return false
    return true


func _run() -> void:
    var partition := WorldPartition3D.new()
    root.add_child(partition)
    var origin := Vector3.ZERO
    var fixed: PackedVector3Array = PackedVector3Array([
        Vector3(4.0, 4.0, 0.65), Vector3(28.0, 27.0, 0.9)])
    var base: NavigationMesh = ForestNavigationMesh.build_tile(origin, partition, fixed)
    if base == null or partition.get_last_navigation_tile_retested_triangle_count() != 512:
        _fail("full 16x16 builder should filter exactly 512 candidate triangles")
        return

    var with_barrier: PackedVector3Array = fixed.duplicate()
    with_barrier.append(Vector3(16, 16, 1.42))
    var patched: NavigationMesh = ForestNavigationMesh.patch_tile(
        origin, partition, base, fixed, with_barrier)
    var tested: int = partition.get_last_navigation_tile_retested_triangle_count()
    if patched == null or tested <= 0 or tested >= 512:
        _fail("changed obstacle did not use a localized incremental triangle patch")
        return
    var complete: NavigationMesh = ForestNavigationMesh.build_tile(origin, partition, with_barrier)
    if not _mesh_equals(patched, complete):
        _fail("incremental insertion differs from full terrain/navmesh build")
        return

    # Both old and new footprints of a moved blocker must be examined.
    var moved: PackedVector3Array = fixed.duplicate()
    moved.append(Vector3(20, 10, 1.42))
    var moved_mesh: NavigationMesh = ForestNavigationMesh.patch_tile(
        origin, partition, patched, with_barrier, moved)
    tested = partition.get_last_navigation_tile_retested_triangle_count()
    if moved_mesh == null or tested <= 0 or tested >= 512:
        _fail("moving a barricade caused excessive or missing native geometry work")
        return
    complete = ForestNavigationMesh.build_tile(origin, partition, moved)
    if not _mesh_equals(moved_mesh, complete):
        _fail("moving an obstacle left stale triangles behind at its previous position")
        return

    var restored: NavigationMesh = ForestNavigationMesh.patch_tile(
        origin, partition, moved_mesh, moved, fixed)
    tested = partition.get_last_navigation_tile_retested_triangle_count()
    if not _mesh_equals(restored, base) or tested >= 512:
        _fail("incremental removal did not restore the original NavMesh polygon graph")
        return

    var reorder: PackedVector3Array = PackedVector3Array([
        fixed[1], fixed[0]])
    var same: NavigationMesh = ForestNavigationMesh.patch_tile(
        origin, partition, base, fixed, reorder)
    if same != base or partition.get_last_navigation_tile_retested_triangle_count() != 0:
        _fail("order-only changes should reuse the cached NavMesh resource")
        return

    var near_terrain: NavigationMesh = ForestNavigationMesh.build_tile(
        Vector3(32, 0, 0), partition, PackedVector3Array())
    var checked: int = partition.get_last_navigation_tile_retested_triangle_count()
    if near_terrain == null or checked != 512:
        _fail("a new neighboring forest cell should still use a full initial build")
        return
    # Adjacent terrain uses exactly the same world-space boundary samples.
    var west: PackedVector3Array = ForestNavigationMesh.sample_vertices(origin)
    var east: PackedVector3Array = ForestNavigationMesh.sample_vertices(Vector3(32, 0, 0))
    for z in range(ForestNavigationMesh.SAMPLE_COUNT + 1):
        var west_edge: Vector3 = west[z * 17 + 16] + Vector3(0, 0, 0)
        var east_edge: Vector3 = east[z * 17] + Vector3(32, 0, 0)
        if west_edge.distance_to(east_edge) > 0.0001:
            _fail("incremental tile API changed the world-space terrain seam")
            return

    print("Incremental NavMesh smoke PASSED: exact full-mesh polygon equivalence for add/move/remove, locality, cache-hit and seamless terrain")
    quit(0)
