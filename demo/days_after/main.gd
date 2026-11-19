extends Node3D
## Self-contained playable survival slice. Engine-generic systems belong in Cgame;
## game rules and inventory remain here.

const SURVIVAL = preload("res://survival_state.gd")
const PLAYER = preload("res://player.gd")

var _survival = SURVIVAL.new()
var _player
var _hud: Label
var _prompt: Label
var _message: Label
var _hud_elapsed := 0.0
var _game_over := false


func _ready() -> void:
    _setup_input()
    _build_world()
    _player = PLAYER.new()
    _player.name = "Survivor"
    _player.position = Vector3(0.0, 1.1, 7.0)
    add_child(_player)
    _player.interaction_requested.connect(_on_interaction_requested)
    _build_hud()
    _refresh_hud()


func _process(delta: float) -> void:
    if _game_over:
        return
    _survival.tick(delta)
    if not _survival.is_alive():
        _game_over = true
        _player.set_physics_process(false)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _message.text = "Вы погибли от голода или жажды. Перезапустите сцену."
    _hud_elapsed += delta
    if _hud_elapsed >= 0.2:
        _hud_elapsed = 0.0
        _refresh_hud()


func _physics_process(_delta: float) -> void:
    if _game_over or _player == null:
        return
    var target = _player.get_look_target()
    if target != null and target.is_in_group("days_after_loot"):
        _prompt.text = "E — подобрать: %s" % String(target.get_meta("item_id", "предмет"))
    else:
        _prompt.text = ""


func _unhandled_input(event: InputEvent) -> void:
    if _game_over:
        return
    if event.is_action_pressed("use_water"):
        _message.text = "Вы выпили воду." if _survival.use_item("water") else "Воды в инвентаре нет."
        _refresh_hud()
    elif event.is_action_pressed("use_food"):
        _message.text = "Вы поели." if _survival.use_item("food") else "Еды в инвентаре нет."
        _refresh_hud()


func _on_interaction_requested(target: CollisionObject3D) -> void:
    if _game_over or not is_instance_valid(target) or not target.is_in_group("days_after_loot"):
        return
    var item_id := String(target.get_meta("item_id", ""))
    var amount := int(target.get_meta("amount", 0))
    if _survival.add_item(item_id, amount):
        _message.text = "Найдено: %s × %d" % [item_id, amount]
        target.queue_free()
        _refresh_hud()


func _setup_input() -> void:
    _bind_key("move_forward", KEY_W)
    _bind_key("move_backward", KEY_S)
    _bind_key("move_left", KEY_A)
    _bind_key("move_right", KEY_D)
    _bind_key("jump", KEY_SPACE)
    _bind_key("sprint", KEY_SHIFT)
    _bind_key("interact", KEY_E)
    _bind_key("use_water", KEY_1)
    _bind_key("use_food", KEY_2)
    _bind_key("toggle_mouse", KEY_ESCAPE)


func _bind_key(action: String, key: Key) -> void:
    if InputMap.has_action(action):
        return
    InputMap.add_action(action)
    var event := InputEventKey.new()
    event.physical_keycode = key
    InputMap.action_add_event(action, event)


func _build_world() -> void:
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.12, 0.17, 0.19)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.65, 0.71, 0.73)
    environment.ambient_light_energy = 0.75
    world.environment = environment
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    add_child(sun)

    _static_box("Ground", Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0), Color(0.28, 0.34, 0.27))
    _static_box("Road", Vector3(0.0, 0.04, -8.0), Vector3(5.5, 0.08, 36.0), Color(0.21, 0.22, 0.22))
    _static_box("RuinLeft", Vector3(-7.0, 2.0, -6.0), Vector3(0.75, 4.0, 11.0), Color(0.48, 0.46, 0.42))
    _static_box("RuinBack", Vector3(-10.0, 1.8, -11.0), Vector3(6.0, 3.6, 0.8), Color(0.44, 0.43, 0.39))
    _static_box("RuinRight", Vector3(7.5, 1.5, -8.0), Vector3(0.8, 3.0, 12.0), Color(0.48, 0.46, 0.42))
    _static_box("Checkpoint", Vector3(3.0, 0.65, -3.0), Vector3(1.5, 1.3, 1.0), Color(0.37, 0.31, 0.25))
    _static_box("Crate", Vector3(-2.0, 0.45, -1.0), Vector3(0.9, 0.9, 0.9), Color(0.34, 0.27, 0.20))

    _spawn_loot("water", Vector3(0.0, 0.36, 4.6), Color(0.22, 0.52, 0.92), 2)
    _spawn_loot("food", Vector3(-1.1, 0.36, 1.0), Color(0.78, 0.53, 0.18), 2)
    _spawn_loot("scrap", Vector3(2.2, 0.36, -1.3), Color(0.60, 0.66, 0.68), 3)
    _spawn_loot("water", Vector3(-3.4, 0.36, -6.3), Color(0.22, 0.52, 0.92), 1)
    _spawn_loot("food", Vector3(3.2, 0.36, -10.0), Color(0.78, 0.53, 0.18), 1)


func _static_box(node_name: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = pos
    var collider := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    collider.shape = box
    body.add_child(collider)

    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.85
    visual.material_override = material
    body.add_child(visual)
    add_child(body)
    return body


func _spawn_loot(item_id: String, pos: Vector3, color: Color, amount: int) -> void:
    var loot := _static_box("Loot_" + item_id, pos, Vector3(0.65, 0.65, 0.65), color)
    loot.add_to_group("days_after_loot")
    loot.set_meta("item_id", item_id)
    loot.set_meta("amount", amount)


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    _hud = Label.new()
    _hud.position = Vector2(18.0, 18.0)
    _hud.add_theme_font_size_override("font_size", 20)
    layer.add_child(_hud)

    _prompt = Label.new()
    _prompt.position = Vector2(18.0, 156.0)
    _prompt.add_theme_font_size_override("font_size", 22)
    layer.add_child(_prompt)

    _message = Label.new()
    _message.position = Vector2(18.0, 204.0)
    _message.add_theme_font_size_override("font_size", 19)
    _message.text = "Осмотрите заброшенный блокпост. Смотрите вниз на предметы."
    layer.add_child(_message)


func _refresh_hud() -> void:
    if _hud == null:
        return
    _hud.text = "DAYS AFTER | HP %d | Голод %d | Жажда %d\nВода: %d  Еда: %d  Металл: %d\nWASD — идти | Shift — бег | Space — прыжок\nE — подобрать | 1 — вода | 2 — еда | Esc — курсор" % [
        roundi(_survival.health), roundi(_survival.hunger), roundi(_survival.thirst),
        _survival.get_count("water"), _survival.get_count("food"), _survival.get_count("scrap")
    ]
