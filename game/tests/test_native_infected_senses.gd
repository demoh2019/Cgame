extends RefCounted
## Native Cgame perception must not circumvent existing server authoritative
## detection rules; stock Godot runs these checks using the empty fallback.

const NativeSenses = preload("res://scripts/shared/native_infected_senses.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
    t.current = "Native perception bridge safely detects engine capabilities"
    var senses := NativeSenses.new()
    t.eq(senses.has_native_vision(), ClassDB.class_exists("AIVisualSensor2D"),
        "vision support is negotiated through the native class registry")
    t.eq(senses.has_native_hearing(), ClassDB.class_exists("AIHearingSensor2D"),
        "hearing support is negotiated through the native class registry")

    t.current = "Native vision remembers the last confirmed position only"
    senses.record_confirmed_sight(Vector2.ZERO, Vector2(8, 0), 20.0, true, 0.1)
    if senses.has_native_vision():
        t.check(senses.remembers_sight(), "accepted LOS creates temporary sight memory")
        t.eq(senses.last_seen_position(), Vector2(8, 0), "last seen position is stored")
        senses.record_confirmed_sight(Vector2.ZERO, Vector2(18, 0), 20.0, false, 0.1)
        t.eq(senses.last_seen_position(), Vector2(8, 0),
            "hidden target motion never leaks into sight memory")
        senses.advance_time(7.0)
        t.check(not senses.remembers_sight(),
            "native sight memory expires after tracking stops")
        senses.reset()
        t.check(not senses.remembers_sight(), "reset clears native visual memory")
    else:
        t.check(not senses.remembers_sight(), "stock Godot omits native visual memory")

    t.current = "Native hearing records only caller-accepted sounds"
    t.check(not senses.record_confirmed_sound(Vector2.ZERO, Vector2(80, 0), 20.0),
        "sound outside listening range cannot forge memory")
    if senses.has_native_hearing():
        t.check(senses.record_confirmed_sound(Vector2.ZERO, Vector2(12, 0), 20.0),
            "an accepted sound is recorded by native hearing")
        t.eq(senses.last_heard_position(), Vector2(12, 0),
            "hearing preserves accepted event location")
        senses.advance_time(4.0)
        t.check(not senses.remembers_sound(), "sound memory expires in real seconds")
    else:
        t.check(not senses.remembers_sound(), "stock Godot has a safe no-op fallback")


    t.current = "Ranked audible stimuli prefer stronger sources and stable order"
    var left_first := NativeSenses.new()
    var right_first := NativeSenses.new()
    if left_first.has_ranked_hearing() and right_first.has_ranked_hearing():
        t.check(left_first.record_confirmed_sound(Vector2.ZERO, Vector2(12, 0), 20.0),
            "weak accepted sound starts native memory")
        t.check(left_first.record_confirmed_sound(Vector2.ZERO, Vector2(4, 0), 20.0),
            "stronger confirmed sound replaces weaker one")
        t.check(left_first.record_confirmed_sound(Vector2.ZERO, Vector2(16, 0), 20.0),
            "a subsequent weaker sound remains audible")
        t.eq(left_first.last_heard_position(), Vector2(4, 0),
            "weak accepted sounds cannot overwrite stronger sound memory")
        t.check(right_first.record_confirmed_sound(Vector2.ZERO, Vector2(4, 0), 20.0),
            "second listener receives the same events in reverse order")
        t.check(right_first.record_confirmed_sound(Vector2.ZERO, Vector2(12, 0), 20.0),
            "second listener also hears the weaker event")
        t.eq(right_first.last_heard_position(), left_first.last_heard_position(),
            "confirmed sound ranking is independent of input order")
        t.near(float(left_first.get_debug_snapshot()["sound_strength"]), 0.8, 0.0001,
            "debug strength comes from native accepted-event clarity")
        left_first.advance_time(4.0)
        t.check(not left_first.remembers_sound(), "priority does not prevent sound expiry")
        t.eq(float(left_first.get_debug_snapshot()["sound_strength"]), 0.0,
            "expired sound memory clears stored strength")
    else:
        t.check(not left_first.has_ranked_hearing(),
            "stock Godot and older Cgame retain legacy hearing safely")

    t.current = "Native multi-source history only retains confirmed perceptions"
    var history_senses := NativeSenses.new()
    t.eq(history_senses.has_native_history(), ClassDB.class_exists("AIStimulusHistory2D"),
        "multi-source history is detected through native class availability")
    history_senses.record_confirmed_sight(Vector2.ZERO, Vector2(6, 0), 20.0,
        true, 0.1, 101)
    history_senses.record_confirmed_sight(Vector2.ZERO, Vector2(18, 0), 20.0,
        false, 0.1, 101) # Occluded movement MUST NOT leak to stored history.
    if history_senses.has_native_history() and history_senses.has_native_vision():
        var best_sight: Dictionary = history_senses.best_confirmed_stimulus(0)
        t.eq(best_sight.get("position"), Vector2(6, 0),
            "visual memory stores only the last confirmed position")
        t.eq(best_sight.get("source_id"), 101,
            "native memory tags an authoritative server-known source ID")
    else:
        t.check(history_senses.best_confirmed_stimulus(0).is_empty(),
            "stock Godot safely returns an empty visual history")

    t.current = "Confirmed sound history preserves independent source lifetimes"
    history_senses.record_confirmed_sound(Vector2.ZERO, Vector2(4, 0), 20.0, 11)
    history_senses.advance_time(2.0)
    history_senses.record_confirmed_sound(Vector2.ZERO, Vector2(16, 0), 20.0, 12)
    history_senses.record_confirmed_sound(Vector2.ZERO, Vector2(80, 0), 20.0, 99)
    if history_senses.has_native_history() and history_senses.has_native_hearing():
        var first_sound: Dictionary = history_senses.best_confirmed_stimulus(1)
        t.eq(first_sound.get("source_id"), 11,
            "stronger unexpired sound still wins while it is active")
        history_senses.advance_time(1.6)
        t.check(not history_senses.remembers_sound(),
            "ranked primary sound memory expires even when weak noise remains")
        var later_sound: Dictionary = history_senses.best_confirmed_stimulus(1)
        t.eq(later_sound.get("source_id"), 12,
            "a separately confirmed sound can outlive the primary ranked sound")
        t.eq(later_sound.get("position"), Vector2(16, 0),
            "secondary investigation location is still server-confirmed")
        var recent: Array = history_senses.get_recent_confirmed_stimuli()
        t.eq(recent.size(), 2,
            "expired stronger sound is gone while younger sound and sight persist")
        var view: Dictionary = history_senses.get_debug_snapshot()
        t.eq(view.get("stimulus_count"), 2,
            "server diagnostic reports the bounded active event history")
        history_senses.reset()
        t.eq(history_senses.get_recent_confirmed_stimuli().size(), 0,
            "reset clears all source-tagged events")
    else:
        t.eq(history_senses.get_recent_confirmed_stimuli().size(), 0,
            "stock Godot has no additional native stimulus data")

    t.current = "Existing authoritative zombie hearing populates native memory"
    var height: float = WorldGen.HUB_HEIGHT
    var world := WorldGen.new(42)
    var infected := Zombie.new(972, "walker", Vector3(0.0, height, 0.0))
    var rng := RandomNumberGenerator.new()
    rng.seed = 972
    var players := {41: {"position": Vector3(12.0, height, 0.0),
        "alive": true, "safe": false, "noise": Defs.SPRINT_NOISE_RADIUS}}
    infected.think(world, players, 0.1, rng)
    if ClassDB.class_exists("AIHearingSensor2D"):
        t.check(infected._native_senses != null,
            "server accepted hearing instantiates the optional native cache")
        if infected._native_senses != null:
            t.check(infected._native_senses.remembers_sound(),
                "native bridge remembers the authoritative sound event")
            t.eq(infected._native_senses.last_heard_position(), Vector2(12, 0),
                "native cache stores the detected survivor position")
    t.eq(infected.target_id, 41,
        "native sensing does not change the existing authoritative target decision")
    var server_debug: Dictionary = infected.get_ai_debug_snapshot()
    t.eq(server_debug.get("zombie_id"), 972,
        "server diagnostic identifies the infected being inspected")
    t.eq(server_debug.get("target_id"), 41,
        "server diagnostic reports actual AI target")
    t.check(server_debug.has("perception"),
        "server diagnostic includes a non-mutating native perception view")
    var native_debug: Dictionary = senses.get_debug_snapshot()
    t.eq(native_debug.get("native_hearing"), senses.has_native_hearing(),
        "native sensing reports its true capability")
    t.check(native_debug.has("sight_memory_seconds") and native_debug.has("sound_memory_seconds"),
        "perception snapshot exposes remaining memory lifetimes")


    t.current = "Chase recovery can investigate a second confirmed sound"
    var secondary_memory := NativeSenses.new()
    secondary_memory.record_confirmed_sound(Vector2.ZERO, Vector2(4, 0), 20.0, 11)
    secondary_memory.advance_time(2.0)
    secondary_memory.record_confirmed_sound(Vector2.ZERO, Vector2(16, 0), 20.0, 12)
    secondary_memory.advance_time(1.6)
    if secondary_memory.has_native_history() and secondary_memory.has_native_hearing():
        var searching := Zombie.new(974, "walker", Vector3(0.0, height, 0.0))
        searching._native_senses = secondary_memory
        searching.target_id = 41
        searching.state = Zombie.State.CHASE
        searching.think_timer = 1.0
        searching.last_known_target = Vector2(-30, 0)
        searching.think(world, {41: {"position": Vector3(1000.0, height, 0.0),
            "alive": true, "safe": false, "noise": 0.0}}, 0.1, rng)
        t.eq(searching.target_id, -1, "lost chase releases the distant combat target")
        t.eq(searching.state, Zombie.State.INVESTIGATE,
            "a lost target triggers investigation rather than a new attack")
        t.eq(searching.last_known_target, Vector2(16, 0),
            "search uses the remaining authoritative secondary sound location")

    t.current = "Optional per-infected native decision trace captures real authoritative scans"
    var traced := Zombie.new(975, "walker", Vector3(0.0, height, 0.0))
    var untraced := Zombie.new(976, "walker", Vector3(0.0, height, 0.0))
    t.check(not bool(traced.get_ai_trace_snapshot().get("enabled", false)),
        "ordinary zombies do not allocate or enable tracing")
    var native_trace: bool = ClassDB.class_exists("AIBehaviorTrace")
    t.eq(traced.enable_ai_trace(true), native_trace,
        "native server trace can be opted in only when class exists")
    var trace_players := {41: {"position": Vector3(12.0, height, 0.0),
        "alive": true, "safe": false, "noise": Defs.SPRINT_NOISE_RADIUS}}
    traced.think(world, trace_players, 0.1, rng)
    untraced.think(world, trace_players, 0.1, rng)
    t.eq(traced.target_id, untraced.target_id,
        "enabling diagnostics never changes target selection")
    if native_trace:
        var trace_debug: Dictionary = traced.get_ai_debug_snapshot()
        var trace_snapshot: Dictionary = trace_debug.get("trace", {})
        t.check(bool(trace_snapshot.get("enabled", false)),
            "native server diagnostic exposes opt-in execution trace")
        var steps: Array = trace_snapshot.get("steps", [])
        t.eq(steps.size(), 1, "the actual target-selection pass records one stage")
        if steps.size() == 1:
            var stage: Dictionary = steps[0]
            t.eq(stage.get("path"), "target_selection",
                "trace identifies the exact server AI phase")
            t.eq(stage.get("task_class"), "ZombieTargetSelection",
                "trace names the authoritative implementation")
            t.eq(int(stage.get("status", -1)), 0,
                "successful authorized target selection records success")
            t.check(int(stage.get("duration_usec", -1)) >= 0,
                "server trace reports nonnegative decision CPU microseconds")
        t.check(not bool(untraced.get_ai_trace_snapshot().get("enabled", false)),
            "other NPCs remain untraced independently")
        t.eq(traced.get_ai_trace_history_frames().size(), 1,
            "opted-in NPC remembers its first authoritative decision tick")
        traced.think_timer = 0.0
        traced.think(world, trace_players, 0.1, rng)
        t.eq(traced.get_ai_trace_history_frames().size(), 2,
            "second server decision creates the next replay frame")
        t.check(not traced.get_ai_slowest_trace_nodes(1).is_empty(),
            "on-demand native server hotspots include real target-selection work")
        var changed: Array = traced.get_ai_trace_history_frames(true)
        t.check(not changed.is_empty(),
            "server can request meaningful decision changes without CPU jitter")
        # The bounded replay buffer must never grow with server uptime.
        for extra_tick in 10:
            traced.think_timer = 2.0 # Avoid making a new selection unnecessarily.
            traced.think(world, trace_players, 0.01, rng)
        t.eq(traced.get_ai_trace_history_frames().size(), 8,
            "server history is capped at eight ticks for one opted-in NPC")
        var server_history_debug: Dictionary = traced.get_ai_debug_snapshot()
        t.check(server_history_debug.has("trace_history") and
            server_history_debug.has("slowest_ai_phases"),
            "server-only debug output exposes bounded replay and CPU hotspots")
        t.eq(untraced.get_ai_trace_history_frames().size(), 0,
            "untraced NPCs do not allocate per-tick histories")
        var traced_visual: Dictionary = traced.get_ai_state_visual_snapshot()
        var traced_visual_nodes: Array = traced_visual.get("nodes", [])
        if traced_visual_nodes.size() == 8:
            var selection_record: Dictionary = traced_visual_nodes[7]
            t.check(bool(selection_record.get("executed", false)),
                "visual inspector highlights an actually traced selection pass")
            t.eq(int(selection_record.get("status", -1)), 0,
                "visual inspector copies the native success status")
        t.check(traced.enable_ai_trace(false), "server can disable and release tracing")
        traced.think_timer = 0.0
        traced.think(world, trace_players, 0.1, rng)
        t.check(not bool(traced.get_ai_trace_snapshot().get("enabled", false)),
            "disabled server traces remain empty")
        t.eq(traced.get_ai_trace_history_frames().size(), 0,
            "disabling tracing releases all replay history")
    else:
        t.check(traced.get_ai_trace_snapshot().get("steps", []).is_empty(),
            "stock Godot has a safe empty trace fallback")
        t.check(traced.get_ai_trace_history_frames().is_empty(),
            "stock Godot safely returns no native replay history")
        t.check(traced.get_ai_slowest_trace_nodes().is_empty(),
            "stock Godot safely returns no native CPU hotspot reports")

    t.current = "Server AI inspector renders real zombie state machine without leaking clients"
    var visual: Dictionary = traced.get_ai_state_visual_snapshot()
    var visual_nodes: Array = visual.get("nodes", [])
    t.eq(int(visual.get("node_count", -1)), 8,
        "server state-machine inspector exposes root, six states and target selection")
    t.eq(visual_nodes.size(), 8, "the inspector node count matches the returned hierarchy")
    if visual_nodes.size() == 8:
        var visual_root: Dictionary = visual_nodes[0]
        t.eq(visual_root.get("task_class"), "ZombieStateMachine",
            "server diagnostics correctly identify the state machine, not a behavior tree")
        t.eq(visual_root.get("path"), "root", "hierarchy has a stable root path")
        var active_count := 0
        for index in range(1, 7):
            var state_record: Dictionary = visual_nodes[index]
            if bool(state_record.get("executed", false)):
                active_count += 1
                t.eq(index - 1, traced.state,
                    "only the actual current infected state is highlighted")
                t.eq(int(state_record.get("status", -1)), 2,
                    "the alive active zombie state is running")
        t.eq(active_count, 1, "exactly one authoritative AI state is currently active")
        var scanned: Dictionary = visual_nodes[7]
        t.eq(scanned.get("path"), "root/6",
            "target selection is exposed as its own diagnostic phase")
        t.check(not bool(scanned.get("executed", false)),
            "disabled native tracing leaves target selection visibly unvisited")
    var visual_debug: Dictionary = traced.get_ai_debug_snapshot().get("visual_tree", {})
    t.eq(int(visual_debug.get("node_count", -1)), visual_nodes.size(),
        "existing server diagnostics embed the same private inspector hierarchy")
    var resting_visual: Dictionary = untraced.get_ai_state_visual_snapshot()
    t.check(not bool(resting_visual.get("trace_enabled", false)),
        "inspector does not enable native tracing for unrelated game NPCs")
    # Inspector data is produced on demand; no client network packet or
    # automatic per-frame state collection is introduced.

    t.current = "Optional per-infected AI profiling is disabled by default"
    t.check(not bool(infected.get_ai_profile_snapshot().get("enabled", false)),
        "ordinary infected do not allocate native timing counters")
    var has_profiler := ClassDB.class_exists("AIExecutionProfiler")
    t.eq(infected.enable_ai_profiling(true), has_profiler,
        "native profiling is enabled only on a custom fork")
    if has_profiler:
        var profile_before: Dictionary = infected.get_ai_profile_snapshot()
        t.check(bool(profile_before.get("enabled", false)),
            "profiler is active on the selected infected only")
        infected.think(world, players, 0.3, rng)
        var recorded: Dictionary = infected.get_ai_profile_snapshot()
        var categories: Dictionary = recorded.get("categories", {})
        var selection: Dictionary = categories.get("target_selection", {})
        t.check(int(selection.get("count", 0)) >= 1,
            "a real server target-selection tick produces timing data")
        t.check(int(selection.get("max_usec", -1)) >= 0,
            "recorded microsecond duration is nonnegative")
        var server_profile: Dictionary = infected.get_ai_debug_snapshot().get("profiling", {})
        t.eq(server_profile.get("total_samples"), recorded.get("total_samples"),
            "debug snapshot includes the actual per-NPC timings")
        infected.enable_ai_profiling(false)
        var samples_before := int(infected.get_ai_profile_snapshot().get("total_samples", 0))
        infected.think(world, players, 0.3, rng)
        t.eq(infected.get_ai_profile_snapshot().get("total_samples"), samples_before,
            "disabled profiling does not collect new samples")
        infected.reset_ai_profile()
        t.eq(infected.get_ai_profile_snapshot().get("total_samples"), 0,
            "per-infected performance counters can reset independently")
    else:
        t.check(not bool(infected.get_ai_profile_snapshot().get("enabled", false)),
            "stock Godot preserves no-op profiling behavior")

    t.current = "Safe-zone players never create native hearing stimulus"
    var protected := Zombie.new(973, "walker", Vector3(0.0, height, 0.0))
    protected.think(world, {41: {"position": Vector3(12.0, height, 0.0),
        "alive": true, "safe": true, "noise": Defs.GUNSHOT_NOISE_RADIUS}},
        0.1, rng)
    t.eq(protected.target_id, -1, "protected survivors remain immune")
    t.check(protected._native_senses == null,
        "immune survivors never enter native sensor memory")
