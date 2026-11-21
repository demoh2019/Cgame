extends SceneTree
## Native bounded cell-path routing integrated with quest waypoint guidance.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_cell_routes.gd

const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const SCENE_PATH: String = "res://cells/forest_cell.tscn"


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest cell routing smoke FAILED: " + reason)
    quit(1)


func _run() -> void:
    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    root.add_child(stream)

    # A missing middle cell forces a four-hop shortest cardinal route.
    for cell in [
            Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
            Vector2i(2, 1), Vector2i(2, 0)]:
        stream.set_cell_scene(cell, SCENE_PATH)

    var start: Vector3 = Vector3(1, 0, 1)
    var goal: Vector3 = Vector3(70, 0, 1)
    var route: Array = QuestNavigation.cell_route(stream, start, goal)
    if route.size() != 5 or route[0] != Vector2i.ZERO             or route[1] != Vector2i(0, 1) or route[4] != Vector2i(2, 0):
        _fail("native shortest path did not route around an unregistered gap")
        return
    var waypoint: Vector3 = QuestNavigation.next_cell_waypoint(stream, route)
    if waypoint.distance_to(Vector3(16, 0, 48)) > 0.001:
        _fail("quest guidance used an incorrect intermediate cell center")
        return

    if not QuestNavigation.cell_route(stream, start, goal, true).is_empty():
        _fail("loaded_only route crossed scenes that are not instantiated")
        return

    # A new scene registration opens a shorter direct corridor.
    stream.set_cell_scene(Vector2i(1, 0), SCENE_PATH)
    route = QuestNavigation.cell_route(stream, start, goal)
    if route.size() != 3 or route[1] != Vector2i(1, 0):
        _fail("route did not replan after a registered shortcut appeared")
        return
    if QuestNavigation.next_cell_waypoint(stream, route) == Vector3.ZERO:
        _fail("multi-cell route lost its intermediate waypoint")
        return
    # For a one-hop route the next waypoint is the actual quest target,
    # not the center of its cell.
    route = QuestNavigation.cell_route(stream, start, Vector3(36, 0, 1))
    if route.size() != 2 or QuestNavigation.next_cell_waypoint(stream, route) != Vector3.ZERO:
        _fail("adjacent-cell route should not override direct quest guidance")
        return

    stream.remove_cell_scene(Vector2i(1, 0))
    stream.remove_cell_scene(Vector2i(1, 1))
    if not QuestNavigation.cell_route(stream, start, goal).is_empty():
        _fail("route crossed a disconnected topology")
        return

    if not QuestNavigation.cell_route(null, start, goal).is_empty():
        _fail("missing WorldPartition3D must not create a fictional path")
        return

    print("Forest cell route smoke PASSED: cardinal shortest path, gap, shortcut, disconnected, loaded-only and quest waypoint")
    quit(0)
