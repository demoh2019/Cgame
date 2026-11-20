extends SceneTree
## End-to-end streamed cross-cell navigation and local NPC avoidance.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_navigation_routes.gd
## Geometry-only supercover checks do not require a loaded navmesh; path
## requests and patrol checks DO require real NavigationServer sync.

const HOME: Vector2i = Vector2i.ZERO
const EAST: Vector2i = Vector2i(1, 0)
const MAX_FRAMES: int = 900


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Cross-cell navigation smoke FAILED: " + reason)
    quit(1)


func _wait_navigation(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_navigation_ready(cell):
            return true
        await physics_frame
    return false


func _run() -> void:
    var scene := load("res://world.tscn") as PackedScene
    if scene == null:
        _fail("playable world scene could not load")
        return
    var world := scene.instantiate() as Node3D
    if world == null:
        _fail("world root is not Node3D")
        return
    root.add_child(world)
    var stream := world.get_node_or_null("WorldPartition_32m") as WorldPartition3D
    var player := world.get_node_or_null("ExplorerBody") as CharacterBody3D
    if stream == null or player == null:
        _fail("missing native streamer or explorer")
        return

    player.call("teleport_to_ground", 0.0, 9.0,
        world.call("height_at", 0.0, 9.0))
    if not stream.pin_cell(HOME) or not stream.pin_cell(EAST):
        _fail("cannot pin adjacent navigation tiles")
        return
    stream.update_streaming()
    if not await _wait_navigation(stream, HOME) \
            or not await _wait_navigation(stream, EAST):
        _fail("neighboring navmesh tiles never synchronized")
        return

    var from := Vector3(8.0, world.call("height_at", 8.0, 12.0), 12.0)
    var to := Vector3(40.0, world.call("height_at", 40.0, 12.0), 12.0)
    var cells: Array = stream.get_navigation_route_cells(from, to)
    if cells.size() != 2 or cells[0] != HOME or cells[1] != EAST:
        _fail("route corridor did not include both adjacent grid cells")
        return
    if not stream.is_navigation_route_ready(from, to):
        _fail("fully synchronized adjacent cell corridor not marked ready")
        return
    var route: PackedVector3Array = stream.get_streamed_navigation_path(
        from, to, true, 1, 16)
    if route.size() < 2 or route[route.size() - 1].distance_to(to) > 4.0:
        _fail("native streamed path returned empty or incomplete cross-cell path")
        return

    var diagonal: Array = stream.get_navigation_route_cells(
        Vector3(1.0, 0.0, 1.0), Vector3(65.0, 0.0, 65.0))
    if diagonal != [
            Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1),
            Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
            Vector2i(2, 2)]:
        _fail("supercover corner crossing skipped an adjacent tile")
        return
    if not stream.get_navigation_route_cells(from, to, 1).is_empty():
        _fail("max-cells budget silently truncated a route")
        return

    var home_tile: Node3D = stream.get_cell_node(HOME)
    var guard := home_tile.get_node_or_null("ForestPatrol") as CharacterBody3D
    if guard == null:
        _fail("home tile lacks native-gated patrol NPC")
        return
    var navigator := guard.get_node_or_null("PatrolNavigationAgent") as NavigationAgent3D
    if navigator == null:
        _fail("NPC has no local avoidance/navigation agent")
        return
    for i in range(16):
        await physics_frame
    if not navigator.avoidance_enabled or int(guard.get("avoidance_velocity_updates")) == 0:
        _fail("NavigationAgent avoidance did not produce safe motion updates")
        return
    var tree_avoidance: int = 0
    for node in home_tile.get_children():
        if node is NavigationObstacle3D:
            tree_avoidance += 1
    if tree_avoidance < 1 or tree_avoidance > 11:
        _fail("per-cell avoidance obstacles are missing or unbounded")
        return

    # Patrol occasionally chooses an east-neighbor waypoint, but only after
    # asking the new native API for a complete route through loaded tiles.
    var previous_crossings: int = int(guard.get("intercell_route_count"))
    for i in range(5):
        guard.call("_advance_waypoint")
    if int(guard.get("intercell_route_count")) <= previous_crossings:
        _fail("NPC did not select any confirmed neighboring-cell route")
        return

    # Keep home pinned but unload EAST by moving the player well away.
    # Scene readiness of HOME must not mask missing corridor navigation.
    stream.unpin_cell(EAST)
    player.call("teleport_to_ground", 160.0, 0.0,
        world.call("height_at", 160.0, 0.0))
    stream.update_streaming()
    if stream.is_cell_loaded(EAST) or stream.is_cell_navigation_ready(EAST):
        _fail("unloaded neighbor retained navigation readiness")
        return
    if stream.is_navigation_route_ready(from, to):
        _fail("route corridor stayed ready after neighbor unload")
        return
    if not stream.get_streamed_navigation_path(from, to).is_empty():
        _fail("native path query returned a path across unloaded navigation")
        return

    stream.unpin_cell(HOME)
    stream.update_streaming()
    print("Cross-cell navigation smoke PASSED: DDA, real route, NPC avoidance, bounded obstacles and safe unload")
    quit(0)
