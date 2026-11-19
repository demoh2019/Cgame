extends SceneTree
## Deterministic navigation regression with static ruins and dynamic defenses.
## godot --headless --path demo/days_after --script res://smoke_test_navigation.gd


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Days After navigation: " + reason)
    quit(1)


func _run() -> void:
    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        _fail("Failed to load scene")
        return
    var game := packed.instantiate()
    root.add_child(game)
    var nav = game.get_node_or_null("InfectedNavigation")
    var survivor = game.get_node_or_null("Player")
    var construction = game.get_node_or_null("Construction")
    var infected = game.get_node_or_null("InfectedScavenger")
    if nav == null or survivor == null or construction == null or infected == null:
        _fail("Missing nav, character, construction or infected")
        return
    if infected.navigation != nav:
        _fail("Infected not connected to path planner")
        return

    # A 10m ruined wall occupies x=-6, z=-7..3 and blocks direct crossing.
    var origin := Vector3(-9.0, 1.0, -2.0)
    var goal := Vector3(-3.0, 1.0, -2.0)
    var route: Array[Vector3] = nav.get_path(origin, goal)
    if route.size() < 10:
        _fail("Path did not detour around the ruined wall")
        return
    for point in route:
        var cell := Vector2i(roundi(point.x), roundi(point.z))
        if nav.is_blocked(cell):
            _fail("Planned path crosses solid static geometry")
            return

    # Dynamic construction updates the blocked cells and revision immediately.
    var pad_cell := Vector2i(-2, 9)
    if nav.is_blocked(pad_cell):
        _fail("Empty construction pad was incorrectly blocked")
        return
    var before_revision: int = nav.revision
    survivor.add_item("wood_t1", 2)
    survivor.add_item("stone_t1", 1)
    if not construction.build_nearest(survivor):
        _fail("Could not build the first barricade")
        return
    if not nav.is_blocked(pad_cell) or nav.revision <= before_revision:
        _fail("Barricade was not added to pathfinding solids")
        return
    var barrier = construction.defenses[0]
    var after_build_revision: int = nav.revision
    barrier.take_damage(1000.0)
    if construction.get_built_count() != 0:
        _fail("Destroyed barrier still in construction map")
        return
    if nav.is_blocked(pad_cell) or nav.revision <= after_build_revision:
        _fail("Destroyed barrier still blocks routes")
        return

    # Rebuilt ruins remain solid after navigation refresh (update() footgun).
    if not nav.is_blocked(Vector2i(-6, -2)):
        _fail("Refreshing navigation cleared static obstacles")
        return
    var reroute: Array[Vector3] = nav.get_path(origin, goal)
    if reroute.is_empty():
        _fail("Route disappeared after dynamic rebuild")
        return

    game.queue_free()
    await process_frame
    print("PASS: Days After AStar ruin avoidance, dynamic barricade paths and zombie navigation wiring.")
    quit(0)
