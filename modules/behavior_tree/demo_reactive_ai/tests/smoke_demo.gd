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

    var demo: Variant = packed.instantiate()
    root.add_child(demo)
    demo.set_physics_process(false)
    await physics_frame
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

    _set_flag(demo.brain, "health", 100)
    _set_flag(demo.brain, "retreat_at_or_below", 30)
    _set_flag(demo.brain, "target_visible", true)
    _set_flag(demo.brain, "target_remembered", true)
    demo.brain.tick(0.2)
    var debug_state: Dictionary = demo.brain.get_debug_snapshot()
    if debug_state.get("root_task_class") != "BehaviorTreeReactiveSelector":
        _fail("Native debug snapshot must identify the active tree")
        return
    if debug_state.get("blackboard", {}).get("health") != 100:
        _fail("Native debug snapshot must include current health")
        return
    var profile_data: Dictionary = demo.brain.get_profile_snapshot()
    var profile_categories: Dictionary = profile_data.get("categories", {})
    var behavior_timings: Dictionary = profile_categories.get("behavior_tree", {})
    if not demo.brain.is_profiling_enabled() or int(behavior_timings.get("count", 0)) != 1:
        _fail("Native behavior runner must profile its first AI tick")
        return
    if int(behavior_timings.get("last_usec", -1)) < 0:
        _fail("Runner profiling must report a nonnegative time")
        return
    if demo.brain.get_blackboard().get("action") != "chase":
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

    _set_flag(demo.brain, "target_visible", false)
    _set_flag(demo.brain, "target_remembered", true)
    demo.brain.tick(0.2)
    if demo.brain.get_blackboard().get("action") != "investigate":
        _fail("Last-seen position should trigger investigation")
        return

    _set_flag(demo.brain, "health", 20)
    demo.brain.tick(0.2)
    if demo.brain.get_blackboard().get("action") != "retreat":
        _fail("Low health must preempt other tasks")
        return

    demo.sensor.reset()
    if demo.sensor.has_target_memory():
        _fail("Reset must clear perception memory")
        return

    # The native timeout decorator must abort a running child, without
    # leaking its execution memory or blocking subsequent behavior trees.
    var timeout := BehaviorTreeTimeout.new()
    timeout.duration = 0.4
    var long_action := BehaviorTreeWait.new()
    long_action.duration = 3.0
    timeout.task = long_action
    var timed_runner := BehaviorTreeRunner.new()
    timed_runner.root_task = timeout
    root.add_child(timed_runner)
    if timed_runner.tick(0.2) != BehaviorTreeTask.RUNNING:
        _fail("Timed AI child should initially remain running")
        return
    if timed_runner.tick(0.2) != BehaviorTreeTask.FAILURE:
        _fail("Time limit must abort a long-running child at its deadline")
        return
    if not timed_runner.get_debug_snapshot().get("execution_memory", {}).is_empty():
        _fail("Timeout must clear the cancelled subtree's execution memory")
        return
    timed_runner.queue_free()

    # The same simulation-time cooldown ledger also drives pack howls in
    # the canonical server and voice events in this playable sandbox.
    if not demo.player_action_cooldowns.try_trigger(&"smoke_shout", 0.8):
        _fail("Native player ability must start ready")
        return
    if demo.player_action_cooldowns.try_trigger(&"smoke_shout", 0.8):
        _fail("Cooldown must reject repeated immediate shouts")
        return
    demo.player_action_cooldowns.advance_time(0.8)
    if not demo.player_action_cooldowns.try_trigger(&"smoke_shout", 0.8):
        _fail("Cooldown must recover after simulation time has elapsed")
        return

    print("PASS: AI perception, wall LOS, memory, reactive priorities and reset")
    quit(0)


func _fail(message: String) -> void:
    push_error(message)
    quit(1)


func _set_flag(brain: BehaviorTreeRunner, key: StringName, value: Variant) -> void:
    var state := brain.get_blackboard()
    state[key] = value
    brain.set_blackboard(state)
