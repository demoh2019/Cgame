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

var player_position := Vector2(160, 350)
var enemy_position := Vector2(760, 350)
var enemy_forward := Vector2.LEFT
var enemy_health := 100
var patrol_direction := -1.0
var ai_timer := 0.0
var current_action := "patrol"
var last_status := BehaviorTree.SUCCESS
var brain := BehaviorTree.new()
var sensor := AIVisualSensor2D.new()
var hud: Label


func _ready() -> void:
    sensor.sight_radius = VISION_RADIUS
    sensor.lose_sight_radius = VISION_RADIUS + 50.0
    sensor.field_of_view_degrees = VISION_FOV
    sensor.memory_duration = 2.5

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

    var retreat := {
        "type": "reactive_sequence",
        "children": [
            {"type": "condition", "key": "low_health", "equals": true},
            {"type": "set", "key": "action", "value": "retreat"},
            {"type": "wait", "ticks": 2}
        ]
    }
    var chase := {
        "type": "reactive_sequence",
        "children": [
            {"type": "condition", "key": "target_visible", "equals": true},
            {"type": "set", "key": "action", "value": "chase"},
            {"type": "wait", "ticks": 2}
        ]
    }
    var investigate := {
        "type": "reactive_sequence",
        "children": [
            {"type": "condition", "key": "target_remembered", "equals": true},
            {"type": "set", "key": "action", "value": "investigate"},
            {"type": "wait", "ticks": 2}
        ]
    }
    var priorities := {
        "type": "reactive_selector",
        "children": [
            retreat, chase, investigate,
            {"type": "set", "key": "action", "value": "patrol"}
        ]
    }
    if not brain.set_tree(priorities):
        push_error("BehaviorTree definition was rejected.")
        set_physics_process(false)
        return

    hud = Label.new()
    hud.position = Vector2(22, 18)
    hud.add_theme_font_size_override("font_size", 17)
    hud.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
    add_child(hud)
    _update_hud()


func _physics_process(delta: float) -> void:
    var movement := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var motion := movement * PLAYER_SPEED * delta
    player_position = _move_around_wall(player_position, motion, PLAYER_RADIUS)

    ai_timer += delta
    if ai_timer >= AI_TICK_SECONDS:
        ai_timer -= AI_TICK_SECONDS
        # World physics determines LOS; the reusable C++ sensor evaluates the
        # current FOV, range hysteresis, and last-known-position memory.
        sensor.observe(enemy_position, enemy_forward, player_position, _has_line_of_sight(), AI_TICK_SECONDS)
        brain.set_blackboard_value("low_health", enemy_health <= 30)
        brain.set_blackboard_value("target_visible", sensor.is_target_visible())
        brain.set_blackboard_value("target_remembered", sensor.has_target_memory())
        brain.set_blackboard_value("last_known_position", sensor.get_last_known_position())
        last_status = brain.tick()
        current_action = str(brain.get_blackboard_value("action", "patrol"))

    var enemy_motion := Vector2.ZERO
    match current_action:
        "patrol":
            enemy_motion = Vector2(patrol_direction * ENEMY_SPEED * delta, 0)
            if enemy_position.x < 615.0:
                patrol_direction = 1.0
            elif enemy_position.x > 880.0:
                patrol_direction = -1.0
        "chase":
            enemy_motion = enemy_position.direction_to(player_position) * ENEMY_SPEED * delta
            if enemy_position.distance_to(player_position) < 25.0:
                enemy_motion = Vector2.ZERO
        "investigate":
            var destination: Vector2 = sensor.get_last_known_position()
            if enemy_position.distance_to(destination) > 10.0:
                enemy_motion = enemy_position.direction_to(destination) * ENEMY_SPEED * delta
        "retreat":
            enemy_motion = enemy_position.direction_to(player_position) * -ENEMY_SPEED * 1.5 * delta

    var next_position := _move_around_wall(enemy_position, enemy_motion, ENEMY_RADIUS)
    if next_position.distance_to(enemy_position) > 0.001:
        enemy_forward = (next_position - enemy_position).normalized()
    enemy_position = next_position

    _update_hud()
    queue_redraw()


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
    elif event.keycode == KEY_R:
        enemy_health = 100
        player_position = Vector2(160, 350)
        enemy_position = Vector2(760, 350)
        enemy_forward = Vector2.LEFT
        patrol_direction = -1.0
        current_action = "patrol"
        last_status = BehaviorTree.SUCCESS
        ai_timer = 0.0
        sensor.reset()
        brain.reset()
        brain.clear_blackboard()


func _update_hud() -> void:
    if hud == null:
        return
    var status_text := "RUNNING" if last_status == BehaviorTree.RUNNING else ("SUCCESS" if last_status == BehaviorTree.SUCCESS else "FAILURE")
    hud.text = "VISUAL PERCEPTION + BEHAVIOR TREE | Arrows: move | Space: attack | R: reset\n"
    hud.text += "Enemy HP: %d | AI: %s | Tree: %s | Visible: %s\n" % [enemy_health, current_action, status_text, str(sensor.is_target_visible())]
    hud.text += "Target memory: %.1f s | Gray wall blocks LOS | Yellow X = last seen position" % sensor.get_memory_remaining()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.075, 0.085, 0.13))
    draw_rect(WALL_RECT, Color(0.54, 0.55, 0.61))
    draw_rect(WALL_RECT.grow(3.0), Color(0.85, 0.85, 0.95, 0.4), false, 3.0)
    var half_fov := deg_to_rad(VISION_FOV * 0.5)
    draw_arc(enemy_position, VISION_RADIUS, enemy_forward.angle() - half_fov, enemy_forward.angle() + half_fov, 72, Color(1.0, 0.36, 0.3, 0.38), 2.0)
    draw_arc(player_position, HIT_RADIUS, 0.0, TAU, 48, Color(0.3, 0.7, 1.0, 0.35), 2.0)
    if sensor.has_target_memory() and not sensor.is_target_visible():
        var last: Vector2 = sensor.get_last_known_position()
        draw_line(last + Vector2(-8, -8), last + Vector2(8, 8), Color.YELLOW, 3.0)
        draw_line(last + Vector2(8, -8), last + Vector2(-8, 8), Color.YELLOW, 3.0)
    draw_circle(player_position, PLAYER_RADIUS, Color(0.26, 0.65, 1.0))
    draw_circle(enemy_position, ENEMY_RADIUS, Color(0.95, 0.34, 0.32) if enemy_health > 30 else Color(1.0, 0.76, 0.27))
    draw_line(enemy_position, enemy_position + enemy_forward * 32.0, Color(1.0, 0.95, 0.85), 3.0)
