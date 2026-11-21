extends SceneTree
## Run with compiled Cgame:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_dynamic_navmesh.gd
## Checks in-place obstacle creation/removal, native dirty coalescing, per-frame
## rebuild budget, server synchronization/readiness, and NPC route invalidation.

const FOREST: String = "res://cells/forest_cell.tscn"
const TerrainHeight = preload("res://scripts/terrain_height.gd")
const MAX_FRAMES: int = 420
const REMOTE: Vector2i = Vector2i(1, 0)


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Dynamic forest NavMesh smoke FAILED: " + reason)
    quit(1)


func _wait_ready(world: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if world.is_cell_navigation_ready(cell):
            return true
        await physics_frame
        await process_frame
    return false


func _wait_revision(world: WorldPartition3D, cell: Vector2i, revision: int) -> bool:
    for i in range(MAX_FRAMES):
        if world.get_cell_navigation_revision(cell) >= revision                 and world.is_cell_navigation_ready(cell):
            return true
        await physics_frame
        await process_frame
    return false


func _root(world: WorldPartition3D, cell: Vector2i) -> Node3D:
    return world.get_cell_instance(cell)


func _region(cell_root: Node3D) -> NavigationRegion3D:
    return cell_root.get_node_or_null("StreamingNavigationRegion") as NavigationRegion3D


func _run() -> void:
    var player := Node3D.new()
    player.position = Vector3(12, 1.5, 12)
    root.add_child(player)
    var world := WorldPartition3D.new()
    world.cell_size = 32.0
    world.load_radius = 1
    world.unload_radius = 2
    world.detail_radius = 1
    world.navigation_radius = 1
    world.max_instances_per_frame = 2
    world.max_navigation_rebuilds_per_physics_frame = 1
    root.add_child(world)
    world.observer_path = world.get_path_to(player)
    world.set_cell_scene(Vector2i.ZERO, FOREST)
    world.set_cell_scene(REMOTE, FOREST)
    if not await _wait_ready(world, Vector2i.ZERO):
        _fail("home navigation mesh was never ready")
        return
    if not await _wait_ready(world, REMOTE):
        _fail("adjacent streamed navigation mesh was never ready")
        return
    var local_root: Node3D = _root(world, Vector2i.ZERO)
    var remote_root: Node3D = _root(world, REMOTE)
    var original: NavigationMesh = _region(local_root).navigation_mesh
    var previous_polygons: int = original.get_polygon_count()
    if previous_polygons < 5 or world.get_navigation_dirty_cell_count() != 0:
        _fail("initial navigation state unexpected")
        return
    if world.get_cell_navigation_revision(Vector2i.ZERO) != 0             or world.get_cell_navigation_revision(REMOTE) != 0:
        _fail("newly loaded regions should have zero dynamic mesh revisions")
        return

    var generation_before: int = world.get_navigation_mesh_generation()
    var barricade_point: Vector3 = Vector3(16, TerrainHeight.height_at(16, 16), 16)
    if not local_root.call("toggle_dynamic_barricade", barricade_point):
        _fail("failed to create a physical barricade and queue nav rebuild")
        return
    if not world.mark_cell_navigation_dirty(Vector2i.ZERO):
        _fail("a coalesced duplicate dirty request was rejected")
        return
    if world.get_navigation_dirty_cell_count() != 1:
        _fail("duplicate dirty marks were not coalesced into one pending tile")
        return
    if world.is_cell_navigation_ready(Vector2i.ZERO):
        _fail("dirty NavMesh was incorrectly reported server-ready")
        return

    # A second cell can become dirty in the same physics tick; the engine
    # must process at most one successful rebuild per physics frame.
    if not remote_root.call("toggle_dynamic_barricade", Vector3(
            48, TerrainHeight.height_at(48, 16), 16)):
        _fail("failed to create an independent remote barricade")
        return
    if world.get_navigation_dirty_cell_count() != 2:
        _fail("two dirty streamed cells were not tracked independently")
        return
    var before_local: int = world.get_cell_navigation_revision(Vector2i.ZERO)
    var before_remote: int = world.get_cell_navigation_revision(REMOTE)
    world.update_streaming()
    world.update_streaming() # Must not bypass budget by calling twice.
    var changed: int = world.get_cell_navigation_revision(Vector2i.ZERO) - before_local
    changed += world.get_cell_navigation_revision(REMOTE) - before_remote
    if changed > 1:
        _fail("reentrant update_streaming exceeded the one-tile physics budget")
        return
    if not await _wait_revision(world, Vector2i.ZERO, 1):
        _fail("home tile did not finish rebuilding after obstacle insertion")
        return
    if not await _wait_revision(world, REMOTE, 1):
        _fail("remote tile was starved by the native queue")
        return
    if world.get_navigation_dirty_cell_count() != 0:
        _fail("completed dynamic mesh updates remained pending")
        return
    if world.get_navigation_mesh_generation() < generation_before + 2:
        _fail("global path cache generation did not reflect both rebuilt regions")
        return

    var updated: NavigationMesh = _region(local_root).navigation_mesh
    if updated == original or updated.get_polygon_count() >= previous_polygons:
        _fail("dynamic obstacle did not replace the mesh with a smaller walkable surface")
        return
    var barricade: StaticBody3D = local_root.get_node_or_null("DynamicBarricade") as StaticBody3D
    if barricade == null or barricade.collision_layer != 1:
        _fail("buildable obstacle is not a physical collision body")
        return

    # Removing the obstacle restores polygons without reloading scene roots.
    if not local_root.call("toggle_dynamic_barricade", barricade_point):
        _fail("failed to remove the barricade")
        return
    if not await _wait_revision(world, Vector2i.ZERO, 2):
        _fail("NavMesh did not rebuild after obstacle removal")
        return
    if _root(world, Vector2i.ZERO) != local_root:
        _fail("dynamic NavMesh update incorrectly reloaded the scene root")
        return
    if _region(local_root).navigation_mesh.get_polygon_count() != previous_polygons:
        _fail("removing the barrier did not restore the original navigation surface")
        return

    # A real stalker path should be invalidated when any active tile changes.
    var chase_goal := Node3D.new()
    root.add_child(chase_goal)
    chase_goal.global_position = Vector3(
        17, TerrainHeight.height_at(17, 16) + 1.0, 16)
    var stalker := CharacterBody3D.new()
    stalker.set_script(preload("res://scripts/forest_stalker.gd"))
    root.add_child(stalker)
    stalker.call("configure", "dynamic_nav_probe", chase_goal, Vector3(
        10, TerrainHeight.height_at(10, 16) + 1.0, 16), world)
    stalker.call("set_encounter_active", true)
    for i in range(15):
        await physics_frame
    var original_queries: int = int(stalker.get("navmesh_path_queries"))
    if original_queries == 0:
        _fail("real NPC never queried the initial path")
        return
    if not remote_root.call("toggle_dynamic_barricade", Vector3(
            48, TerrainHeight.height_at(48, 16), 16)):
        _fail("failed to modify the remote navigation region again")
        return
    if not await _wait_revision(world, REMOTE, 2):
        _fail("second remote nav revision did not complete")
        return
    for i in range(12):
        await physics_frame
    if int(stalker.get("navmesh_forced_replans")) < 1:
        _fail("NPC did not invalidate a path after the world NavMesh generation changed")
        return
    stalker.queue_free()
    await process_frame
    if world.has_navigation_agent("dynamic_nav_probe"):
        _fail("removed stalker left a registered native navigation agent")
        return

    print("Dynamic NavMesh smoke PASSED: coalesced dirty queue, frame budget, physics fence, real barricades, scene preservation, NPC replanning")
    quit(0)
