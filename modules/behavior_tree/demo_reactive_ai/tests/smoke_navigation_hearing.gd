extends SceneTree
## Run with the custom fork's Godot binary from the demo project path.
## Tests the integration between hearing events, reactive AI and AStarGrid2D.


func _initialize() -> void:
    call_deferred("_run_checks")


func _run_checks() -> void:
    var scene: PackedScene = load("res://main.tscn")
    if scene == null:
        _fail("Game scene failed to load")
        return
    var demo: Variant = scene.instantiate()
    root.add_child(demo)
    demo.set_physics_process(false)
    await physics_frame
    await physics_frame

    if demo.hearing == null or demo.navigation == null:
        _fail("Native hearing or navigation was not initialized")
        return

    var waypoints: PackedVector2Array = demo.call("_navigation_path", Vector2(760, 350), Vector2(160, 350))
    if waypoints.size() < 3:
        _fail("A* route around the wall must have multiple waypoints")
        return

    var occupied := Rect2(465, 205, 35, 280).grow(22)
    var went_around_wall := false
    for point in waypoints:
        if occupied.has_point(point):
            _fail("A* route entered the enemy-inflated wall")
            return
        if point.y < occupied.position.y or point.y > occupied.end.y:
            went_around_wall = true
    if not went_around_wall:
        _fail("A* route did not go around the blocking wall")
        return

    # The player starts behind the wall. A loud event is still audible after
    # the wall attenuation, even though there is no visual line of sight.
    if demo.call("_has_line_of_sight"):
        _fail("Default setup should have a sight-blocking wall")
        return
    if not demo.call("_report_player_noise", 1.0):
        _fail("Loud player noise should be heard through the wall")
        return
    if demo.hearing.get_last_heard_position() != Vector2(160, 350):
        _fail("Hearing did not remember the event position")
        return
    if not demo.hearing.has_sound_memory():
        _fail("Hearing did not retain sound memory")
        return

    demo.brain.set_blackboard_value("low_health", false)
    demo.brain.set_blackboard_value("target_visible", false)
    demo.brain.set_blackboard_value("target_remembered", false)
    demo.brain.set_blackboard_value("sound_remembered", true)
    demo.brain.tick()
    if demo.brain.get_blackboard_value("action") != "investigate_sound":
        _fail("Audible event should trigger investigate_sound branch")
        return

    # A newly visible target outranks hearing, and low health outranks both.
    demo.brain.set_blackboard_value("target_visible", true)
    demo.brain.tick()
    if demo.brain.get_blackboard_value("action") != "chase":
        _fail("Vision should interrupt sound investigation")
        return

    demo.brain.set_blackboard_value("low_health", true)
    demo.brain.tick()
    if demo.brain.get_blackboard_value("action") != "retreat":
        _fail("Emergency retreat should interrupt vision and hearing")
        return

    demo.hearing.reset()
    if demo.hearing.has_sound_memory():
        _fail("Hearing reset should clear event memory")
        return

    print("PASS: hearing, occluded sound, navigation around wall, and AI priorities")
    quit(0)


func _fail(message: String) -> void:
    push_error(message)
    quit(1)
