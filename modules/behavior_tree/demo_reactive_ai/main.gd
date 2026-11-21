extends Node2D
## Playable integration of native BehaviorTree and AIVisualSensor2D.
## Obstacles block line of sight; sensor memory drives investigation behavior.

const PLAYER_SPEED := 260.0
const ENEMY_SPEED := 115.0
const VISION_RADIUS := 240.0
const VISION_FOV := 260.0
const HIT_RADIUS := 65.0
const AI_TICK_SECONDS := 0.2
const PLAYER_RADIUS := 17.0
const ENEMY_RADIUS := 20.0
const WALL_RECT := Rect2(465, 205, 35, 280)
const GRID_STEP := 24.0
const GRID_COLUMNS := 40
const GRID_ROWS := 25

var player_position := Vector2(160, 350)
var enemy_position := Vector2(760, 350)
var enemy_forward := Vector2.LEFT
var enemy_health := 100
var patrol_direction := -1.0
var ai_timer := 0.0
var current_action := "patrol"
var last_status := BehaviorTreeTask.RUNNING
var last_debug_snapshot: Dictionary = {}
var last_profile_snapshot: Dictionary = {}
var brain := BehaviorTreeRunner.new()
var sensor := AIVisualSensor2D.new()
var hearing := AIHearingSensor2D.new()
var navigation := AStarGrid2D.new()
var update_scheduler := AIUpdateScheduler.new()
var navigation_profiler := AIExecutionProfiler.new()
var ai_tick_index := 0
var navigation_path := PackedVector2Array()
var navigation_index := 0
var navigation_goal_cell := Vector2i(-1, -1)
var navigation_action := ""
var footstep_timer := 0.0
var pending_shout := false
var noise_visual_timer := 0.0
var last_noise_position := Vector2.ZERO
var hud: Label


func _ready() -> void:
    sensor.sight_radius = VISION_RADIUS
    sensor.lose_sight_radius = VISION_RADIUS + 50.0
    sensor.field_of_view_degrees = VISION_FOV
    sensor.memory_duration = 2.5
    hearing.hearing_radius = 800.0
    hearing.memory_duration = 3.5
    _build_navigation_grid()
    update_scheduler.slots_per_cycle = 4
    navigation_profiler.enabled = true

    # A real StaticBody2D blocks physics ray queries, even though player and
    # enemy are represented by lightweight procedural circles in this demo.
    var wall := StaticBody2D.new()
    wall.name = "SightBlockingWall"
    wall.position = WALL_RECT.get_center()
    wall.collision_layer = 1
    wall.collision_mask = 0
    var collision := CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = WALL_RECT.size
    collision.shape = rectangle
    wall.add_child(collision)
    add_child(wall)


    # This fork's develop branch uses Resource-backed BehaviorTreeTask nodes,
    # not Dictionary-defined trees. Keep each runner's memory independent.
    var priorities := BehaviorTreeReactiveSelector.new()
    priorities.add_task(_make_guarded_behavior(_make_health_guard(), "retreat"))
    priorities.add_task(_make_behavior("target_visible", "chase"))
    priorities.add_task(_make_behavior("target_remembered", "investigate"))
    priorities.add_task(_make_behavior("sound_remembered", "investigate_sound"))
    priorities.add_task(_make_action("patrol"))
    brain.root_task = priorities
    brain.auto_tick = false
    brain.profiling_enabled = true  # Demo opt-in; gameplay uses disabled-by-default runners.
    add_child(brain)

    hud = Label.new()
    hud.position = Vector2(22, 18)
    hud.add_theme_font_size_override("font_size", 17)
    hud.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
    add_child(hud)
    _update_hud()


func _make_condition(key: StringName) -> BehaviorTreeBlackboardCheck:
    var check := BehaviorTreeBlackboardCheck.new()
    check.key = key
    check.expected_value = true
    return check


func _make_action(action_name: String) -> BehaviorTreeBlackboardSet:
    var action_task := BehaviorTreeBlackboardSet.new()
    action_task.key = &"action"
    action_task.value = action_name
    return action_task


func _make_health_guard() -> BehaviorTreeBlackboardCompare:
    var check := BehaviorTreeBlackboardCompare.new()
    check.key = &"health"
    check.use_other_key = true
    check.other_key = &"retreat_at_or_below"
    check.comparison = BehaviorTreeBlackboardCompare.LESS_OR_EQUAL
    return check


func _make_behavior(flag: StringName, action_name: String) -> BehaviorTreeReactiveSequence:
    return _make_guarded_behavior(_make_condition(flag), action_name)


func _make_guarded_behavior(guard: BehaviorTreeTask, action_name: String) -> BehaviorTreeReactiveSequence:
    var sequence := BehaviorTreeReactiveSequence.new()
    sequence.add_task(guard)
    sequence.add_task(_make_action(action_name))
    var hold := BehaviorTreeWait.new()
    hold.duration = 1.0
    sequence.add_task(hold)
    return sequence


func _physics_process(delta: float) -> void:
    var movement := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var motion := movement * PLAYER_SPEED * delta
    player_position = _move_around_wall(player_position, motion, PLAYER_RADIUS)

    noise_visual_timer = maxf(0.0, noise_visual_timer - delta)
    if movement.length_squared() > 0.0:
        footstep_timer -= delta
        if footstep_timer <= 0.0:
            footstep_timer = 0.7
            _report_player_noise(0.35)
    else:
        footstep_timer = 0.0
    if pending_shout:
        pending_shout = false
        _report_player_noise(1.0)

    ai_timer += delta
    if ai_timer >= AI_TICK_SECONDS:
        ai_timer -= AI_TICK_SECONDS
        ai_tick_index += 1
        # World physics determines LOS; the reusable C++ sensor evaluates the
        # current FOV, range hysteresis, and last-known-position memory.
        sensor.observe(enemy_position, enemy_forward, player_position, _has_line_of_sight(), AI_TICK_SECONDS)
        hearing.advance_time(AI_TICK_SECONDS)
        # A completed runner is explicitly restarted: resource-based runners
        # cache SUCCESS/FAILURE until reset, unlike the previous Dict runtime.
        if brain.is_finished():
            brain.reset()
        brain.set_blackboard({
            "health": enemy_health,
            "retreat_at_or_below": 30,
            "target_visible": sensor.is_target_visible(),
            "target_remembered": sensor.has_target_memory(),
            "last_known_position": sensor.get_last_known_position(),
            "sound_remembered": hearing.has_sound_memory(),
            "last_heard_position": hearing.get_last_heard_position(),
            "action": current_action
        })
        last_status = brain.tick(AI_TICK_SECONDS)
        last_debug_snapshot = brain.get_debug_snapshot()
        last_profile_snapshot = brain.get_profile_snapshot()
        current_action = str(brain.get_blackboard().get("action", "patrol"))

    var enemy_motion := Vector2.ZERO
    match current_action:
        "patrol":
            navigation_action = ""
            enemy_motion = Vector2(patrol_direction * ENEMY_SPEED * delta, 0)
            if enemy_position.x < 615.0:
                patrol_direction = 1.0
            elif enemy_position.x > 880.0:
                patrol_direction = -1.0
        "chase":
            if enemy_position.distance_to(player_position) > 25.0:
                enemy_motion = _navigation_motion(player_position, ENEMY_SPEED * delta)
        "investigate":
            var destination: Vector2 = sensor.get_last_known_position()
            if enemy_position.distance_to(destination) > 10.0:
                enemy_motion = _navigation_motion(destination, ENEMY_SPEED * delta)
        "investigate_sound":
            var sound_destination: Vector2 = hearing.get_last_heard_position()
            if enemy_position.distance_to(sound_destination) > 10.0:
                enemy_motion = _navigation_motion(sound_destination, ENEMY_SPEED * delta)
        "retreat":
            navigation_action = ""
            enemy_motion = enemy_position.direction_to(player_position) * -ENEMY_SPEED * 1.5 * delta

    var next_position := _move_around_wall(enemy_position, enemy_motion, ENEMY_RADIUS)
    if next_position.distance_to(enemy_position) > 0.001:
        enemy_forward = (next_position - enemy_position).normalized()
    enemy_position = next_position

    _update_hud()
    queue_redraw()



func _build_navigation_grid() -> void:
    # Cell centers are obstacle-inflated by the enemy radius so a route never
    # cuts through the wall. This is Godot's built-in AStarGrid2D, not a custom
    # navigation server replacement.
    navigation.region = Rect2i(0, 0, GRID_COLUMNS, GRID_ROWS)
    navigation.cell_size = Vector2(GRID_STEP, GRID_STEP)
    navigation.offset = Vector2(GRID_STEP * 0.5, GRID_STEP * 0.5)
    navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
    navigation.update()
    var blocked := WALL_RECT.grow(ENEMY_RADIUS + 2.0)
    for y in range(GRID_ROWS):
        for x in range(GRID_COLUMNS):
            var center := Vector2((float(x) + 0.5) * GRID_STEP, (float(y) + 0.5) * GRID_STEP)
            if blocked.has_point(center) or center.y < 155.0 or center.y > 560.0:
                navigation.set_point_solid(Vector2i(x, y))


func _cell_for_world(point: Vector2) -> Vector2i:
    return Vector2i(
        clampi(floori(point.x / GRID_STEP), 0, GRID_COLUMNS - 1),
        clampi(floori(point.y / GRID_STEP), 0, GRID_ROWS - 1)
    )


func _navigation_path(from_point: Vector2, goal: Vector2) -> PackedVector2Array:
    var start := _cell_for_world(from_point)
    var finish := _cell_for_world(goal)
    if navigation.is_point_solid(start):
        return PackedVector2Array()
    if navigation.is_point_solid(finish):
        # A near-wall target can be on an enemy-blocked cell. Redirect to the
        # closest reachable neighbor without moving through the wall.
        var best_distance := INF
        var candidate := Vector2i(-1, -1)
        for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
            var neighbor := finish + offset
            if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= GRID_COLUMNS or neighbor.y >= GRID_ROWS:
                continue
            if not navigation.is_point_solid(neighbor):
                var center := Vector2((float(neighbor.x) + 0.5) * GRID_STEP, (float(neighbor.y) + 0.5) * GRID_STEP)
                if center.distance_squared_to(goal) < best_distance:
                    best_distance = center.distance_squared_to(goal)
                    candidate = neighbor
        if candidate.x < 0:
            return PackedVector2Array()
        finish = candidate
    return navigation.get_point_path(start, finish)


func _navigation_motion(goal: Vector2, distance_per_frame: float) -> Vector2:
    var goal_cell := _cell_for_world(goal)
    # Always replan when switching actions. During pursuit, moving targets
    # are refreshed on the NPC's stable slot instead of every grid-cell move.
    # The cached route is safe to follow while the next refresh is pending.
    var forced_replan := current_action != navigation_action or navigation_path.is_empty()
    if forced_replan or (goal_cell != navigation_goal_cell
            and update_scheduler.is_due(93, ai_tick_index)):
        navigation_action = current_action
        navigation_goal_cell = goal_cell
        navigation_profiler.begin_sample(&"navigation_repath")
        navigation_path = _navigation_path(enemy_position, goal)
        navigation_profiler.end_sample(&"navigation_repath")
        navigation_index = 0
    if navigation_path.is_empty():
        return Vector2.ZERO
    while navigation_index < navigation_path.size() and enemy_position.distance_to(navigation_path[navigation_index]) < 7.0:
        navigation_index += 1
    var destination := navigation_path[navigation_path.size() - 1] if navigation_index >= navigation_path.size() else navigation_path[navigation_index]
    return enemy_position.direction_to(destination) * minf(distance_per_frame, enemy_position.distance_to(destination))


func _report_player_noise(loudness: float) -> bool:
    # Hearing does not require visual LOS. A wall attenuates, not silences,
    # the signal; a separate AIHearingSensor2D handles distance and memory.
    var attenuation := 0.8 if not _has_line_of_sight() else 1.0
    var heard: bool = hearing.report_noise(enemy_position, player_position, loudness, attenuation)
    last_noise_position = player_position
    noise_visual_timer = 0.6
    return heard


func _move_around_wall(from_position: Vector2, motion: Vector2, radius: float) -> Vector2:
    var bounds := get_viewport_rect().size
    var wall_bounds := WALL_RECT.grow(radius)
    var result := from_position
    var x_candidate := Vector2(clampf(result.x + motion.x, radius, bounds.x - radius), result.y)
    if not wall_bounds.has_point(x_candidate):
        result.x = x_candidate.x
    var y_candidate := Vector2(result.x, clampf(result.y + motion.y, 110.0 + radius, bounds.y - radius))
    if not wall_bounds.has_point(y_candidate):
        result.y = y_candidate.y
    return result


func _has_line_of_sight() -> bool:
    # Player and NPC are not CollisionObject2D; only the wall is on layer 1.
    var query := PhysicsRayQueryParameters2D.create(enemy_position, player_position, 1)
    return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    if not event.pressed or event.echo:
        return
    if event.keycode == KEY_SPACE and player_position.distance_to(enemy_position) <= HIT_RADIUS:
        enemy_health = maxi(0, enemy_health - 35)
    elif event.keycode == KEY_F:
        # Schedule sound emission in the next physics frame.
        pending_shout = true
    elif event.keycode == KEY_P:
        brain.profiling_enabled = not brain.is_profiling_enabled()
        brain.reset_profile()
        last_profile_snapshot = brain.get_profile_snapshot()
    elif event.keycode == KEY_R:
        enemy_health = 100
        player_position = Vector2(160, 350)
        enemy_position = Vector2(760, 350)
        enemy_forward = Vector2.LEFT
        patrol_direction = -1.0
        current_action = "patrol"
        last_status = BehaviorTreeTask.RUNNING
        last_debug_snapshot = {}
        ai_tick_index = 0
        navigation_profiler.reset()
        brain.reset_profile()
        last_profile_snapshot = brain.get_profile_snapshot()
        ai_timer = 0.0
        sensor.reset()
        hearing.reset()
        brain.reset()
        brain.set_blackboard({})
        navigation_path = PackedVector2Array()
        navigation_goal_cell = Vector2i(-1, -1)
        navigation_action = ""
        footstep_timer = 0.0
        pending_shout = false
        noise_visual_timer = 0.0


func _update_hud() -> void:
    if hud == null:
        return
    var status_text := "RUNNING" if last_status == BehaviorTreeTask.RUNNING else ("SUCCESS" if last_status == BehaviorTreeTask.SUCCESS else "FAILURE")
    hud.text = "SIGHT + HEARING + A* NAVIGATION | Arrows: move | F: shout | Space: hit | P: profile | R: reset\n"
    hud.text += "Enemy HP: %d | AI: %s | Tree: %s | Visible: %s\n" % [enemy_health, current_action, status_text, str(sensor.is_target_visible())]
    hud.text += "Sight: %.1fs | Sound: %.1fs | Gray wall blocks LOS | Yellow X = last seen position" % [sensor.get_memory_remaining(), hearing.get_memory_remaining()]
    # Update diagnostic snapshots only at logical AI ticks, not render frames.
    var cursors: Dictionary = last_debug_snapshot.get("execution_memory", {})
    hud.text += "\nNative Blackboard guard: HP <= %d | Running node memories: %d" % [30, cursors.size()]
    var categories: Dictionary = last_profile_snapshot.get("categories", {})
    var decision: Dictionary = categories.get("behavior_tree", {})
    hud.text += "\nAI profiler: %s | Decision: %d ticks, avg %.1f us, max %d us" % [
        "ON" if brain.is_profiling_enabled() else "OFF",
        int(decision.get("count", 0)),
        float(decision.get("mean_usec", 0.0)),
        int(decision.get("max_usec", 0))
    ]
    var path_rows: Dictionary = navigation_profiler.get_snapshot().get("categories", {})
    var path_cost: Dictionary = path_rows.get("navigation_repath", {})
    hud.text += "\nScheduled A* repaths: %d | Mean path query: %.1f us | Next slot in %d ticks" % [
        int(path_cost.get("count", 0)),
        float(path_cost.get("mean_usec", 0.0)),
        update_scheduler.ticks_until_due(93, ai_tick_index)
    ]


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.075, 0.085, 0.13))
    draw_rect(WALL_RECT, Color(0.54, 0.55, 0.61))
    draw_rect(WALL_RECT.grow(3.0), Color(0.85, 0.85, 0.95, 0.4), false, 3.0)
    var half_fov := deg_to_rad(VISION_FOV * 0.5)
    draw_arc(enemy_position, VISION_RADIUS, enemy_forward.angle() - half_fov, enemy_forward.angle() + half_fov, 72, Color(1.0, 0.36, 0.3, 0.38), 2.0)
    draw_arc(player_position, HIT_RADIUS, 0.0, TAU, 48, Color(0.3, 0.7, 1.0, 0.35), 2.0)
    if noise_visual_timer > 0.0:
        draw_arc(last_noise_position, 55.0 * (1.0 - noise_visual_timer), 0.0, TAU, 48, Color(0.3, 0.95, 0.8, 0.6), 3.0)
    if hearing.has_sound_memory() and not sensor.is_target_visible():
        draw_arc(hearing.get_last_heard_position(), 12.0, 0.0, TAU, 24, Color(0.35, 0.95, 0.8), 2.0)
    if navigation_path.size() > 1 and current_action in ["chase", "investigate", "investigate_sound"]:
        for index in range(1, navigation_path.size()):
            draw_line(navigation_path[index - 1], navigation_path[index], Color(0.3, 0.85, 0.7, 0.42), 2.0)
    if sensor.has_target_memory() and not sensor.is_target_visible():
        var last: Vector2 = sensor.get_last_known_position()
        draw_line(last + Vector2(-8, -8), last + Vector2(8, 8), Color.YELLOW, 3.0)
        draw_line(last + Vector2(8, -8), last + Vector2(-8, 8), Color.YELLOW, 3.0)
    draw_circle(player_position, PLAYER_RADIUS, Color(0.26, 0.65, 1.0))
    draw_circle(enemy_position, ENEMY_RADIUS, Color(0.95, 0.34, 0.32) if enemy_health > 30 else Color(1.0, 0.76, 0.27))
    draw_line(enemy_position, enemy_position + enemy_forward * 32.0, Color(1.0, 0.95, 0.85), 3.0)
