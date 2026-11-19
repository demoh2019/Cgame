extends Node3D

## First playable Days After slice: one small scavenging area. All scenery
## uses procedural Godot primitives so the demo has no external asset dependencies.

const PLAYER_SCRIPT = preload("res://player.gd")
const PICKUP_SCRIPT = preload("res://pickup.gd")
const DAY_NIGHT_SCRIPT = preload("res://day_night.gd")

var player
var hud_label: Label
var prompt_label: Label
var day_night
var _campfires := 0
var _message := ""
var _message_seconds := 0.0


func _ready() -> void:
    _configure_controls()
    _build_world()
    _build_player()
    _build_pickups()
    _build_day_night()
    _build_hud()


func _configure_controls() -> void:
    _bind_key("move_forward", KEY_W)
    _bind_key("move_back", KEY_S)
    _bind_key("move_left", KEY_A)
    _bind_key("move_right", KEY_D)
    _bind_key("sprint", KEY_SHIFT)
    _bind_key("jump", KEY_SPACE)
    _bind_key("interact", KEY_E)
    _bind_key("consume_food", KEY_1)
    _bind_key("consume_water", KEY_2)
    _bind_key("craft_campfire", KEY_F)
    _bind_key("restart", KEY_R)


func _bind_key(action_name: String, key_code: int) -> void:
    # Preserve user-defined mappings if the action is already configured.
    if InputMap.has_action(action_name):
        return
    InputMap.add_action(action_name)
    var key_event := InputEventKey.new()
    key_event.physical_keycode = key_code
    InputMap.action_add_event(action_name, key_event)


func _build_world() -> void:
    var environment_node := WorldEnvironment.new()
    environment_node.name = "Atmosphere"
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#65747b")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#a0a4a0")
    environment.ambient_light_energy = 0.5
    environment_node.environment = environment
    add_child(environment_node)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation = Vector3(-0.9, -0.6, 0.1)
    sun.light_energy = 1.2
    add_child(sun)

    _add_static_box("Ground", Vector3(0.0, -0.5, 0.0),
        Vector3(40.0, 1.0, 40.0), Color("#53604b"))

    # Simple ruined structures with real physical collision.
    _add_static_box("RuinedWallWest", Vector3(-6.0, 1.2, -2.0),
        Vector3(0.8, 2.4, 10.0), Color("#77746d"))
    _add_static_box("RuinedWallNorth", Vector3(5.0, 1.0, -7.0),
        Vector3(8.0, 2.0, 0.8), Color("#77746d"))
    _add_static_box("ConcreteBlock", Vector3(3.5, 0.75, -2.5),
        Vector3(1.5, 1.5, 1.5), Color("#98948d"))
    _add_static_box("AbandonedShelter", Vector3(-2.0, 1.2, -9.0),
        Vector3(3.0, 2.4, 2.0), Color("#62645f"))
    _add_static_box("RoadBarrier", Vector3(-2.0, 0.5, 0.0),
        Vector3(1.5, 1.0, 0.65), Color("#ba925f"))


func _add_static_box(body_name: String, center: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = body_name
    body.position = center

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.9
    mesh_instance.material_override = material
    body.add_child(mesh_instance)
    add_child(body)


func _build_player() -> void:
    player = PLAYER_SCRIPT.new()
    player.name = "Player"
    player.position = Vector3(0.0, 1.05, 7.0)

    var collision := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.38
    shape.height = 1.8
    collision.shape = shape
    player.add_child(collision)

    var head := Node3D.new()
    head.name = "Head"
    head.position.y = 0.55
    player.add_child(head)

    var camera := Camera3D.new()
    camera.name = "Camera3D"
    camera.current = true
    head.add_child(camera)

    var ray := RayCast3D.new()
    ray.name = "AimRay"
    ray.target_position = Vector3(0.0, 0.0, -3.2)
    ray.collide_with_areas = true
    ray.collide_with_bodies = false
    camera.add_child(ray)

    add_child(player)


func _build_pickups() -> void:
    _add_pickup("FoodCrate", "food", "консервы", Vector3(0.0, 1.0, 3.5), 2)
    _add_pickup("WaterCan", "water", "бутылка воды", Vector3(2.0, 1.0, 1.0), 1)
    _add_pickup("FoodCache", "food", "провизия", Vector3(-3.5, 1.0, -5.0), 1)
    _add_pickup("WaterStash", "water", "фляга", Vector3(2.0, 1.0, -6.0), 2)
    _add_pickup("WoodPileA", "wood", "доски", Vector3(0.0, 1.0, 4.8), 1)
    _add_pickup("WoodPileB", "wood", "брёвна", Vector3(3.0, 1.0, 3.0), 1)
    _add_pickup("WoodPileC", "wood", "ветки", Vector3(-3.5, 1.0, 2.5), 1)
    _add_pickup("StonePileA", "stone", "камни", Vector3(4.5, 1.0, 1.5), 1)
    _add_pickup("StonePileB", "stone", "обломки", Vector3(-3.5, 1.0, -1.0), 1)


func _add_pickup(node_name: String, kind: String, title: String,
        location: Vector3, count: int) -> void:
    var pickup = PICKUP_SCRIPT.new()
    pickup.name = node_name
    pickup.item_type = kind
    pickup.display_name = title
    pickup.quantity = count
    pickup.position = location
    add_child(pickup)


func _build_day_night() -> void:
    day_night = DAY_NIGHT_SCRIPT.new()
    day_night.name = "DayNight"
    add_child(day_night)


func _build_hud() -> void:
    var ui := CanvasLayer.new()
    ui.name = "HUD"
    add_child(ui)

    var panel := PanelContainer.new()
    panel.position = Vector2(16, 16)
    ui.add_child(panel)

    var padding := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        padding.add_theme_constant_override("margin_" + side, 12)
    panel.add_child(padding)

    var column := VBoxContainer.new()
    padding.add_child(column)
    hud_label = Label.new()
    column.add_child(hud_label)

    var help_label := Label.new()
    help_label.text = "WASD — ходьба | Shift — бег | Space — прыжок\n" + \
        "E — подобрать | 1 — съесть | 2 — выпить | F — костёр\n" + \
        "Esc — освободить мышь | ЛКМ — вернуть | R — заново"
    column.add_child(help_label)

    prompt_label = Label.new()
    prompt_label.position = Vector2(18, 170)
    ui.add_child(prompt_label)

    var crosshair := Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 24)
    ui.add_child(crosshair)
    crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _process(delta: float) -> void:
    if player == null or hud_label == null:
        return
    _message_seconds = maxf(0.0, _message_seconds - delta)
    hud_label.text = "DAYS AFTER — ПРОТОТИП | День %d, %s\n" % [
        day_night.day_number, day_night.get_time_label()
    ] + "Здоровье: %d   Голод: %d   Жажда: %d   Выносливость: %d\n" % [
        roundi(player.health), roundi(player.hunger),
        roundi(player.thirst), roundi(player.stamina)
    ] + "Рюкзак: еда × %d   вода × %d   дерево × %d   камень × %d\n" % [
        player.food_count, player.water_count, player.wood_count, player.stone_count
    ] + "Костры: %d   (рецепт: 3 дерева + 2 камня)" % _campfires
    if player.health <= 0.0:
        prompt_label.text = "Вы погибли от истощения. Нажмите R, чтобы начать заново."
    elif _message_seconds > 0.0:
        prompt_label.text = _message
    else:
        var target: Node = player.get_aimed_pickup()
        prompt_label.text = ("[E] Подобрать: " + str(target.get("display_name"))
            if target != null else "Исследуйте руины и найдите припасы.")

    if Input.is_action_just_pressed("craft_campfire"):
        _craft_campfire()
    if Input.is_action_just_pressed("restart"):
        get_tree().reload_current_scene()


func _craft_campfire() -> bool:
    if player == null or player.health <= 0.0:
        return false
    if player.wood_count < 3 or player.stone_count < 2:
        _message = "Нужно собрать 3 дерева и 2 камня."
        _message_seconds = 3.0
        return false

    player.wood_count -= 3
    player.stone_count -= 2
    _campfires += 1
    var campfire := Node3D.new()
    campfire.name = "Campfire_%d" % _campfires
    campfire.position = player.global_position + Vector3(1.6, -0.75, 0.0)

    var base := MeshInstance3D.new()
    var base_mesh := CylinderMesh.new()
    base_mesh.top_radius = 0.8
    base_mesh.bottom_radius = 0.85
    base_mesh.height = 0.25
    base.mesh = base_mesh
    var wood_material := StandardMaterial3D.new()
    wood_material.albedo_color = Color("#6c3b20")
    base.material_override = wood_material
    campfire.add_child(base)

    var ember := MeshInstance3D.new()
    var ember_mesh := SphereMesh.new()
    ember_mesh.radius = 0.4
    ember_mesh.height = 0.65
    ember.mesh = ember_mesh
    ember.position.y = 0.4
    var fire_material := StandardMaterial3D.new()
    fire_material.albedo_color = Color("#ff7a24")
    ember.material_override = fire_material
    campfire.add_child(ember)

    var light := OmniLight3D.new()
    light.position.y = 0.65
    light.light_color = Color("#ff9a43")
    light.light_energy = 1.8
    light.omni_range = 7.0
    campfire.add_child(light)
    add_child(campfire)
    _message = "Костёр построен!"
    _message_seconds = 3.0
    return true
