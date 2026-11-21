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

    # Moving a target to another A* cell should not trigger an immediate
    # expensive repath unless the NPC's deterministic update slot is due.
    if demo.update_scheduler.get_slots_per_cycle() != 4:
        _fail("Native scheduler must have four configured update phases")
        return
    demo.current_action = "chase"
    var due_tick: int = demo.update_scheduler.get_agent_slot(93)
    demo.ai_tick_index = (due_tick + 1) % 4
    demo.call("_navigation_motion", Vector2(160, 350), 8.0)
    var cached_cell: Vector2i = demo.navigation_goal_cell
    var changed_goal := Vector2(110, 350)
    demo.call("_navigation_motion", changed_goal, 8.0)
    if demo.navigation_goal_cell != cached_cell:
        _fail("Nonurgent route changes should wait for the assigned AI slot")
        return
    demo.ai_tick_index = due_tick
    demo.call("_navigation_motion", changed_goal, 8.0)
    if demo.navigation_goal_cell == cached_cell:
        _fail("Next assigned slot must refresh the cached A* destination")
        return
    var profile_data: Dictionary = demo.navigation_profiler.get_snapshot()
    var path_rows: Dictionary = profile_data.get("categories", {})
    if int(path_rows.get("navigation_repath", {}).get("count", 0)) != 2:
        _fail("Native profiler must record only actual A* recalculations")
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
    var history_best: Dictionary = demo.stimulus_history.get_best(AIStimulusHistory2D.SOUND)
    if history_best.get("position", Vector2.INF) != Vector2(160, 350):
        _fail("Confirmed audible noise must enter the new native history")
        return
    if int(history_best.get("source_id", -1)) != 1:
        _fail("Source-aware history must retain the demo survivor ID")
        return
    if demo.stimulus_history.get_event_count() != 1:
        _fail("Demo hearing must not duplicate the confirmed sound")
        return

    _set_flag(demo.brain, "health", 100)
    _set_flag(demo.brain, "retreat_at_or_below", 30)
    _set_flag(demo.brain, "target_visible", false)
    _set_flag(demo.brain, "target_remembered", false)
    _set_flag(demo.brain, "sound_remembered", true)
    demo.brain.tick(0.2)
    if demo.brain.get_blackboard().get("action") != "investigate_sound":
        _fail("Audible event should trigger investigate_sound branch")
        return

    # A newly visible target outranks hearing, and low health outranks both.
    _set_flag(demo.brain, "target_visible", true)
    demo.brain.tick(0.2)
    if demo.brain.get_blackboard().get("action") != "chase":
        _fail("Vision should interrupt sound investigation")
        return

    _set_flag(demo.brain, "health", 20)
    demo.brain.tick(0.2)
    if demo.brain.get_blackboard().get("action") != "retreat":
        _fail("Emergency retreat should interrupt vision and hearing")
        return

    demo.stimulus_history.advance_time(4.0)
    if demo.stimulus_history.get_event_count() != 0:
        _fail("Time-limited stimulus history must evict old sound events")
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


func _set_flag(brain: BehaviorTreeRunner, key: StringName, value: Variant) -> void:
    var state := brain.get_blackboard()
    state[key] = value
    brain.set_blackboard(state)
