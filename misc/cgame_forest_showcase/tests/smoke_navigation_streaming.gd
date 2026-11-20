extends SceneTree
## End-to-end streamed NavigationMesh, native NavigationServer sync and NPC AI.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_navigation_streaming.gd
## No writes to the user's existing savegame.

const HOME: Vector2i = Vector2i.ZERO
const EAST: Vector2i = Vector2i(1, 0)
const MAX_FRAMES: int = 800


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Streaming navigation smoke FAILED: " + message)
    quit(1)


func _wait_navigation(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_navigation_ready(cell):
            return true
        await physics_frame
    return false


func _run() -> void:
    var packed: PackedScene = load("res://world.tscn")
    if packed == null:
        _fail("main game scene could not load")
        return
    var world := packed.instantiate() as Node3D
    if world == null:
        _fail("game root is not Node3D")
        return
    root.add_child(world)
    var stream := world.get_node_or_null("WorldPartition_32m") as WorldPartition3D
    var player := world.get_node_or_null("ExplorerBody") as CharacterBody3D
    if stream == null or player == null:
        _fail("game streamer or player is missing")
        return
    player.call("teleport_to_ground", 0.0, 9.0,
        world.call("height_at", 0.0, 9.0))
    if not stream.pin_cell(HOME) or not stream.pin_cell(EAST):
        _fail("could not hold neighboring cells for navigation checks")
        return
    stream.update_streaming()

    if not await _wait_navigation(stream, HOME):
        _fail("home navigation region never synchronized with NavigationServer")
        return
    if not await _wait_navigation(stream, EAST):
        _fail("adjacent navigation region never synchronized")
        return
    if not stream.is_cell_physics_ready(HOME):
        _fail("nav-ready cell failed prerequisite physics readiness")
        return
    if not stream.are_cells_navigation_ready(HOME, 0):
        _fail("native navigation-region query failed after server sync")
        return
    if stream.get_navigation_ready_cell_count() < 2:
        _fail("ready-cell counter omitted synced neighboring regions")
        return

    var a: Node3D = stream.get_cell_node(HOME)
    var b: Node3D = stream.get_cell_node(EAST)
    var nav_a := a.get_node_or_null("GroundNavigation") as NavigationRegion3D
    var nav_b := b.get_node_or_null("GroundNavigation") as NavigationRegion3D
    if nav_a == null or nav_b == null:
        _fail("streamed forest lacks child NavigationRegion3D nodes")
        return
    if nav_a.navigation_mesh == null or nav_b.navigation_mesh == null:
        _fail("NavigationRegion3D lacks generated navmesh geometry")
        return
    if nav_a.navigation_mesh.get_polygon_count() != 128 \
            or nav_b.navigation_mesh.get_polygon_count() != 128:
        _fail("navmesh polygon budget is not 128 per 32m cell")
        return
    var west_vertices: PackedVector3Array = nav_a.navigation_mesh.vertices
    var east_vertices: PackedVector3Array = nav_b.navigation_mesh.vertices
    if west_vertices.size() != 81 or east_vertices.size() != 81:
        _fail("navmesh should have exactly 81 terrain height samples")
        return
    for z in range(9):
        var west_point: Vector3 = west_vertices[z * 9 + 8]
        var east_point: Vector3 = east_vertices[z * 9]
        var west_world: Vector3 = nav_a.to_global(west_point)
        var east_world: Vector3 = nav_b.to_global(east_point)
        if not west_world.is_equal_approx(east_world):
            _fail("navigation seam heights differ between adjacent tiles")
            return

    var nav_map: RID = nav_a.get_navigation_map()
    var region_rid: RID = nav_a.get_rid()
    if NavigationServer3D.map_get_iteration_id(nav_map) == 0 \
            or NavigationServer3D.region_get_iteration_id(region_rid) == 0:
        _fail("native nav-ready state preceded real NavigationServer sync")
        return

    var guard := a.get_node_or_null("ForestPatrol") as CharacterBody3D
    if guard == null:
        _fail("first streamed home cell has no patrolling NPC")
        return
    var agent := guard.get_node_or_null("PatrolNavigationAgent") as NavigationAgent3D
    if agent == null:
        _fail("patrol NPC lacks a NavigationAgent3D")
        return
    for i in range(6):
        await physics_frame
    if not bool(guard.get("navigation_active")):
        _fail("NPC did not activate when native navigation became ready")
        return
    if int(guard.get("completed_waypoints")) < 1:
        _fail("NPC did not start a real navigation patrol")
        return
    var start: Vector3 = nav_a.to_global(Vector3(6.0,
        world.call("height_at", 6.0, 6.0), 6.0))
    var destination: Vector3 = nav_a.to_global(Vector3(20.0,
        world.call("height_at", 20.0, 20.0), 20.0))
    var route: PackedVector3Array = NavigationServer3D.map_get_path(
        nav_map, start, destination, true)
    if route.size() < 2:
        _fail("NavigationServer produced no navigable route within tile")
        return

    # Disable the navigation region without unloading the terrain. The engine
    # must revoke readiness while the player's collider remains active.
    nav_a.enabled = false
    for i in range(10):
        await physics_frame
    if stream.is_cell_navigation_ready(HOME):
        _fail("disabled region remained incorrectly nav-ready")
        return
    if bool(guard.get("navigation_active")):
        _fail("NPC kept navigating after its region was disabled")
        return
    nav_a.enabled = true
    if not await _wait_navigation(stream, HOME):
        _fail("temporarily disabled region did not resynchronize")
        return

    var unready_events: int = int(world.get("navigation_unready_events"))
    stream.unpin_cell(HOME)
    stream.unpin_cell(EAST)
    player.call("teleport_to_ground", 224.0, 0.0,
        world.call("height_at", 224.0, 0.0))
    stream.update_streaming()
    if stream.is_cell_navigation_ready(HOME) or stream.is_cell_loaded(HOME):
        _fail("unloaded home cell retained nav readiness")
        return
    if int(world.get("navigation_unready_events")) <= unready_events:
        _fail("navigation-unready signal was not forwarded to gameplay")
        return

    print("Streaming navigation smoke PASSED: terrain navmesh seam, NavigationServer sync, NPC patrol, disable/re-enable and unload")
    quit(0)
