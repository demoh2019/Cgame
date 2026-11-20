extends SceneTree
## Headless integration smoke test for native perception and NPC decision making.
## Run: godot --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_demo.gd


func _initialize() -> void:
    call_deferred("_run_checks")


func _run_checks() -> void:
    var packed: PackedScene = load("res://main.tscn")
    if packed == null:
        _fail("Demo scene could not be loaded")
        return

    var demo: Node2D = packed.instantiate()
    root.add_child(demo)
    demo.set_physics_process(false)
    await physics_frame

    if demo.sensor == null or demo.brain == null:
        _fail("Native AI classes were not instantiated")
        return
    if demo.call("_has_line_of_sight"):
        _fail("Default gray wall must block the player/enemy raycast")
        return

    # Move target onto the enemy's side of the obstacle to test detection.
    demo.player_position = Vector2(730, 350)
    if not demo.call("_has_line_of_sight"):
        _fail("Unobstructed ray must report clear LOS")
        return
    demo.sensor.observe(demo.enemy_position, demo.enemy_forward, demo.player_position, true, 0.2)
    if not demo.sensor.is_target_visible():
        _fail("Sensor did not acquire a target in front of the enemy")
        return

    demo.brain.set_blackboard_value("low_health", false)
    demo.brain.set_blackboard_value("target_visible", true)
    demo.brain.set_blackboard_value("target_remembered", true)
    demo.brain.tick()
    if demo.brain.get_blackboard_value("action") != "chase":
        _fail("Visible player must cause chase behavior")
        return

    # The ray is blocked again, but the native sensor retains last-known position.
    demo.player_position = Vector2(160, 350)
    demo.sensor.observe(demo.enemy_position, demo.enemy_forward, demo.player_position, false, 0.2)
    if demo.sensor.is_target_visible() or not demo.sensor.has_target_memory():
        _fail("Occlusion must lose sight but keep temporary memory")
        return
    if demo.sensor.get_last_known_position() != Vector2(730, 350):
        _fail("Occluded targets must not overwrite last seen position")
        return

    demo.brain.set_blackboard_value("target_visible", false)
    demo.brain.set_blackboard_value("target_remembered", true)
    demo.brain.tick()
    if demo.brain.get_blackboard_value("action") != "investigate":
        _fail("Last-seen position should trigger investigation")
        return

    demo.brain.set_blackboard_value("low_health", true)
    demo.brain.tick()
    if demo.brain.get_blackboard_value("action") != "retreat":
        _fail("Low health must preempt other tasks")
        return

    demo.sensor.reset()
    if demo.sensor.has_target_memory():
        _fail("Reset must clear perception memory")
        return

    print("PASS: AI perception, wall LOS, memory, reactive priorities and reset")
    quit(0)


func _fail(message: String) -> void:
    push_error(message)
    quit(1)
