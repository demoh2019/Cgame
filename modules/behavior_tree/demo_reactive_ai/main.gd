extends Node2D
## Small, playable AI sandbox. Requires this fork's built-in BehaviorTree module.

const PLAYER_SPEED := 260.0
const ENEMY_SPEED := 115.0
const VISION_RADIUS := 240.0
const HIT_RADIUS := 65.0
const AI_TICK_SECONDS := 0.2

var player_position := Vector2(160, 350)
var enemy_position := Vector2(660, 350)
var enemy_health := 100
var patrol_direction := 1.0
var ai_timer := 0.0
var current_action := "patrol"
var last_status := BehaviorTree.SUCCESS
var brain := BehaviorTree.new()
var hud: Label


func _ready() -> void:
    # Reactive sequences recheck their guards while waiting. The selector
    # evaluates higher-priority branches each tick, interrupting lower ones.
    var flee := {
        "type": "reactive_sequence",
        "children": [
            {"type": "condition", "key": "low_health", "equals": true},
            {"type": "wait", "ticks": 2},
            {"type": "set", "key": "action", "value": "retreat"}
        ]
    }
    var pursue := {
        "type": "reactive_sequence",
        "children": [
            {"type": "condition", "key": "player_visible", "equals": true},
            {"type": "wait", "ticks": 2},
            {"type": "set", "key": "action", "value": "chase"}
        ]
    }
    var priorities := {
        "type": "reactive_selector",
        "children": [
            flee,
            pursue,
            {"type": "set", "key": "action", "value": "patrol"}
        ]
    }
    if not brain.set_tree(priorities):
        push_error("BehaviorTree definition was rejected.")
        set_physics_process(false)
        return

    hud = Label.new()
    hud.position = Vector2(22, 18)
    hud.add_theme_font_size_override("font_size", 18)
    hud.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
    add_child(hud)
    _update_hud()


func _physics_process(delta: float) -> void:
    var movement := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var bounds := get_viewport_rect().size
    player_position += movement * PLAYER_SPEED * delta
    player_position = player_position.clamp(Vector2(20, 105), bounds - Vector2(20, 20))

    ai_timer += delta
    if ai_timer >= AI_TICK_SECONDS:
        ai_timer -= AI_TICK_SECONDS
        brain.set_blackboard_value("low_health", enemy_health <= 30)
        brain.set_blackboard_value("player_visible", enemy_position.distance_to(player_position) <= VISION_RADIUS)
        last_status = brain.tick()
        current_action = "thinking" if last_status == BehaviorTree.RUNNING else str(brain.get_blackboard_value("action", "patrol"))

    match current_action:
        "patrol":
            enemy_position.x += patrol_direction * ENEMY_SPEED * delta
            if enemy_position.x < 320.0:
                patrol_direction = 1.0
            elif enemy_position.x > bounds.x - 45.0:
                patrol_direction = -1.0
        "chase":
            enemy_position = enemy_position.move_toward(player_position, ENEMY_SPEED * delta)
        "retreat":
            var away := (enemy_position - player_position).normalized()
            if away == Vector2.ZERO:
                away = Vector2.RIGHT
            enemy_position += away * ENEMY_SPEED * 1.5 * delta
    enemy_position = enemy_position.clamp(Vector2(20, 105), bounds - Vector2(20, 20))

    _update_hud()
    queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_SPACE and player_position.distance_to(enemy_position) <= HIT_RADIUS:
        enemy_health = maxi(0, enemy_health - 35)
    elif event.keycode == KEY_R:
        enemy_health = 100
        player_position = Vector2(160, 350)
        enemy_position = Vector2(660, 350)
        current_action = "patrol"
        ai_timer = 0.0
        brain.reset()
        brain.clear_blackboard()


func _update_hud() -> void:
    if hud == null:
        return
    var status_text := "RUNNING" if last_status == BehaviorTree.RUNNING else ("SUCCESS" if last_status == BehaviorTree.SUCCESS else "FAILURE")
    hud.text = "REACTIVE NPC AI  |  Arrow keys: move  |  Space near enemy: hit  |  R: restart\n"
    hud.text += "Enemy health: %d    AI state: %s    Tree status: %s\n" % [enemy_health, current_action, status_text]
    hud.text += "Blue = player   Red = enemy   Ring = enemy vision   Low health <= 30 triggers retreat"


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.075, 0.085, 0.13))
    draw_arc(enemy_position, VISION_RADIUS, 0.0, TAU, 80, Color(1.0, 0.36, 0.3, 0.24), 2.0)
    draw_arc(player_position, HIT_RADIUS, 0.0, TAU, 48, Color(0.3, 0.7, 1.0, 0.35), 2.0)
    draw_circle(player_position, 17.0, Color(0.26, 0.65, 1.0))
    draw_circle(enemy_position, 20.0, Color(0.95, 0.34, 0.32) if enemy_health > 30 else Color(1.0, 0.76, 0.27))
