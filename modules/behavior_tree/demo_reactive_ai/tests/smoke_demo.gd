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
    # A real behavior-tree tick must produce a bounded parent-first task
    # execution history that can be visualized without global tracing.
    var node_trace: Dictionary = demo.brain.get_trace_snapshot()
    if not bool(node_trace.get("enabled", false)):
        _fail("Playable demo should opt into the native per-node AI debugger")
        return
    var visited_nodes: Array = node_trace.get("steps", [])
    if visited_nodes.size() < 4:
        _fail("The first chase decision must record nested native BT nodes")
        return
    var root_record: Dictionary = visited_nodes[0]
    if str(root_record.get("path", "")) != "root" or str(root_record.get("task_class", "")) != "BehaviorTreeReactiveSelector":
        _fail("Native trace must begin at the root reactive selector")
        return
    if int(root_record.get("status", -1)) != BehaviorTreeTask.RUNNING:
        _fail("Trace root status must reflect the running chase branch")
        return
    var nested_path_found := false
    for record in visited_nodes:
        var node: Dictionary = record
        if str(node.get("path", "")).begins_with("root/1/"):
            nested_path_found = true
        if int(node.get("duration_usec", -1)) < 0:
            _fail("Native per-task CPU timings must be nonnegative")
            return
    if not nested_path_found:
        _fail("Native debug trace must capture nested chase branch children")
        return
    if int(node_trace.get("truncated", -1)) != 0:
        _fail("Small demo tree should fit inside its bounded node trace")
        return

    # The full Resource graph includes branches skipped on the current tick.
    var graph: Dictionary = demo.brain.get_tree_snapshot()
    var graph_nodes: Array = graph.get("nodes", [])
    if graph_nodes.size() < visited_nodes.size():
        _fail("Full graph inspector must include all executed and skipped tasks")
        return
    var skipped_patrol := false
    for raw_node in graph_nodes:
        var task: Dictionary = raw_node
        if task.get("path") == "root/4" and not bool(task.get("executed", true)):
            skipped_patrol = true
    if not skipped_patrol:
        _fail("The unvisited patrol alternative must remain visible in the graph")
        return
    demo.call("_refresh_trace_tree_panel")
    if demo.trace_tree == null or demo.trace_panel == null or not demo.trace_panel.visible:
        _fail("Live AI hierarchy panel must be visible while tracing is enabled")
        return
    var visual_root: TreeItem = demo.trace_tree.get_root()
    var first_task: TreeItem = visual_root.get_first_child() if visual_root != null else null
    if first_task == null or first_task.get_text(0) != "ReactiveSelector":
        _fail("The live hierarchical Tree must show the actual native root task")
        return
    if first_task.get_text(1) != "RUNNING":
        _fail("The active root task must be highlighted as running")
        return
    demo.brain.trace_enabled = false
    demo.call("_refresh_trace_tree_panel")
    if demo.trace_panel.visible:
        _fail("Disabling tracing must hide the live debug panel")
        return
    demo.brain.trace_enabled = true
    demo.call("_refresh_trace_tree_panel")

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

    # The sandbox retains replayable decisions instead of only the latest
    # trace. The health retreat above differs from the previous investigation.
    var replay_frames: Array = demo.brain.get_trace_history_frames()
    if replay_frames.size() < 2 or replay_frames.size() > 16:
        _fail("Playable AI debug history must keep bounded multi-tick decisions")
        return
    var changed_frames: Array = demo.brain.get_trace_history_frames(true)
    if changed_frames.size() < 2:
        _fail("Investigation and retreat must register different AI decisions")
        return
    var slow_nodes: Array = demo.brain.get_slowest_trace_nodes(1)
    if slow_nodes.is_empty():
        _fail("The real native AI decision should expose at least one CPU hotspot")
        return
    var slowest: Dictionary = slow_nodes[0]
    if int(slowest.get("self_usec", -1)) < 0 or int(slowest.get("duration_usec", -1)) < int(slowest.get("self_usec", 0)):
        _fail("Own-time hotspot must be nonnegative and bounded by inclusive time")
        return

    demo.call("_replay_previous")
    if demo.trace_replay_tick < 0 or not demo.trace_title.text.contains("REPLAY"):
        _fail("Previous must display a stored decision instead of the live tree")
        return
    demo.call("_replay_next")
    demo.call("_replay_live")
    if demo.trace_replay_tick != -1 or not demo.trace_title.text.contains("LIVE"):
        _fail("Live must restore the latest native AI state")
        return
    demo.call("_set_replay_changes_only", true)
    if not demo.trace_changes_only or not demo.trace_history_label.text.contains("changed-only"):
        _fail("Changed-only replay toggle should filter identical decisions")
        return
    demo.call("_set_replay_changes_only", false)

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
