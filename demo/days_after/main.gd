extends Node3D

## First playable Days After slice: one small scavenging area. All scenery
## uses procedural Godot primitives so the demo has no external asset dependencies.

const PLAYER_SCRIPT = preload("res://player.gd")
const PICKUP_SCRIPT = preload("res://pickup.gd")
const RESOURCE_SCRIPT = preload("res://resource_node.gd")
const ZOMBIE_SCRIPT = preload("res://zombie.gd")
const TRADER_SCRIPT = preload("res://trade_terminal.gd")

var player
var hud_label: Label
var prompt_label: Label
var infected_kills: int = 0
var infected_total: int = 0


func _ready() -> void:
    _configure_controls()
    _build_world()
    _build_player()
    _build_pickups()
    _build_resources()
    _build_trader()
    _build_enemies()
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
    _bind_key("craft_bandage", KEY_3)
    _bind_key("craft_tool", KEY_4)
    _bind_key("use_bandage", KEY_5)
    _bind_key("craft_advanced_bandage", KEY_6)
    _bind_key("use_advanced_bandage", KEY_7)
    _bind_key("restart", KEY_R)
    _bind_key("attack", KEY_F)
    _bind_key("craft_spear", KEY_8)
    _bind_key("craft_vest", KEY_9)
    _bind_key("trade_buy", KEY_B)


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
    player.attack_requested.connect(_on_player_attacked)


func _build_pickups() -> void:
    _add_pickup("FoodCrate", "food", "консервы", Vector3(0.0, 1.0, 3.5), 2)
    _add_pickup("WaterCan", "water", "бутылка воды", Vector3(2.0, 1.0, 1.0), 1)
    _add_pickup("FoodCache", "food", "провизия", Vector3(-3.5, 1.0, -5.0), 1)
    _add_pickup("WaterStash", "water", "фляга", Vector3(2.0, 1.0, -6.0), 2)


func _add_pickup(node_name: String, kind: String, title: String,
        location: Vector3, count: int) -> void:
    var pickup = PICKUP_SCRIPT.new()
    pickup.name = node_name
    pickup.item_type = kind
    pickup.display_name = title
    pickup.quantity = count
    pickup.position = location
    add_child(pickup)


func _build_resources() -> void:
    # Tier 1 harvest unlocks skills; tier 2 requires both skill and crafted tool.
    _add_resource("WoodA", "wood", 1, Vector3(-4.0, 0.55, 4.0), 2)
    _add_resource("WoodB", "wood", 1, Vector3(-4.0, 0.55, -3.0), 2)
    _add_resource("StoneA", "stone", 1, Vector3(4.0, 0.55, 4.0), 2)
    _add_resource("StoneB", "stone", 1, Vector3(4.0, 0.55, -3.0), 2)
    _add_resource("FiberA", "fiber", 1, Vector3(0.0, 0.55, -3.0), 2)
    _add_resource("FiberB", "fiber", 1, Vector3(2.6, 0.55, -4.5), 2)
    _add_resource("FiberT2", "fiber", 2, Vector3(-4.1, 0.55, -5.5), 2)
    _add_resource("WoodT2", "wood", 2, Vector3(12.0, 0.55, 6.0), 2)
    _add_resource("StoneT2", "stone", 2, Vector3(12.0, 0.55, -6.0), 2)


func _add_resource(node_name: String, kind: String, tier: int,
        location: Vector3, count: int) -> void:
    var resource = RESOURCE_SCRIPT.new()
    resource.name = node_name
    resource.resource_kind = kind
    resource.tier = tier
    resource.yield_count = count
    resource.display_name = "%s T%d" % [kind, tier]
    resource.position = location
    add_child(resource)


func _build_trader() -> void:
    var trader = TRADER_SCRIPT.new()
    trader.name = "CampTrader"
    trader.position = Vector3(2.0, 0.75, 5.0)
    add_child(trader)


func _build_enemies() -> void:
    _spawn_infected("InfectedWalker", Vector3(9.0, 1.05, 7.0))
    _spawn_infected("InfectedScavenger", Vector3(-10.0, 1.05, 8.0))
    _spawn_infected("InfectedRoad", Vector3(11.0, 1.05, -2.0))
    _spawn_infected("InfectedNorth", Vector3(-11.0, 1.05, -13.0))


func _spawn_infected(node_name: String, location: Vector3) -> void:
    var infected = ZOMBIE_SCRIPT.new()
    infected.name = node_name
    infected.target = player
    infected.position = location
    infected.eliminated.connect(_on_infected_eliminated)
    add_child(infected)
    infected_total += 1


func _on_player_attacked(damage: float, range_meters: float) -> void:
    var closest: Node3D = null
    var best_distance: float = range_meters
    var forward: Vector3 = -player.global_transform.basis.z
    forward.y = 0.0
    forward = forward.normalized()
    for candidate in get_tree().get_nodes_in_group("infected"):
        if candidate.is_queued_for_deletion():
            continue
        var to_enemy: Vector3 = candidate.global_position - player.global_position
        to_enemy.y = 0.0
        var distance: float = to_enemy.length()
        if distance <= 0.01 or distance > best_distance:
            continue
        if forward.dot(to_enemy / distance) < 0.28:
            continue
        closest = candidate
        best_distance = distance
    if closest != null:
        closest.call("take_damage", damage)
        player.last_message = "Атака: %d урона." % int(damage)


func _on_infected_eliminated() -> void:
    infected_kills += 1
    player.gain_combat_xp(25)
    player.add_item("infected_sample", 1)
    player.last_message = "Заражённый уничтожен! Опыт боя +25."


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
    help_label.text = "WASD движение | Shift бег | Space прыжок | F удар\n" + \
        "E сбор | 1 еда | 2 вода | 3 бинт | 4 инструмент | 5 лечение\n" + \
        "6 улучшенный бинт | 7 лечение | 8 копьё | 9 броня\n" + \
        "E у торговца: продать ресурс | B у торговца: купить воду\n" + \
        "Esc мышь | ЛКМ захват мыши | R перезапуск"
    column.add_child(help_label)

    prompt_label = Label.new()
    prompt_label.position = Vector2(18, 335)
    ui.add_child(prompt_label)

    var crosshair := Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 24)
    ui.add_child(crosshair)
    crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _process(_delta: float) -> void:
    if player == null or hud_label == null:
        return
    hud_label.text = (
        "DAYS AFTER  ×  SANDBOX SURVIVAL\n" +
        "Здоровье %d | Голод %d | Жажда %d\n" % [
            roundi(player.health), roundi(player.hunger), roundi(player.thirst)
        ] +
        "Рюкзак: еда %d, вода %d, древесина %d, камень %d, волокно %d\n" % [
            player.get_item_count("food"), player.get_item_count("water"),
            player.get_item_count("wood_t1"), player.get_item_count("stone_t1"),
            player.get_item_count("fiber_t1")
        ] +
        "T2: дерево %d, камень %d, волокно %d\n" % [
            player.get_item_count("wood_t2"), player.get_item_count("stone_t2"),
            player.get_item_count("fiber_t2")
        ] +
        "Добыча: древесина %d | камень %d | волокно %d | ремесло XP %d\n" % [
            player.gathering_level("wood"), player.gathering_level("stone"),
            player.gathering_level("fiber"), player.crafting_xp
        ] +
        "Бинты: %d / %d | T2 дерево %d, камень %d, волокно %d\n" % [
            player.get_item_count("field_bandage"),
            player.get_item_count("reinforced_bandage"),
            player.get_item_count("wood_t2"), player.get_item_count("stone_t2"),
            player.get_item_count("fiber_t2")
        ] +
        "Снаряжение: оружие %s | броня %s | инструмент %s\n" % [
            player.equipped_weapon if not player.equipped_weapon.is_empty() else "руки",
            player.equipped_armor if not player.equipped_armor.is_empty() else "нет",
            player.equipped_tool if not player.equipped_tool.is_empty() else "нет"
        ] +
        "Заражённые: %d/%d | Боевой опыт %d | Кредиты %d\n" % [
            infected_kills, infected_total, player.combat_xp, player.credits
        ] +
        player.last_message
    )
    if player.health <= 0.0:
        prompt_label.text = "Вы погибли. Нажмите R, чтобы начать заново."
    else:
        var target: Node = player.get_aimed_pickup()
        prompt_label.text = (
            "[E] Взаимодействовать: " + str(target.get("display_name"))
            if target != null else "Исследуйте руины, собирайте T1 и осваивайте T2."
        )
    if Input.is_action_just_pressed("trade_buy") and player.health > 0.0:
        var trade_target: Node = player.get_aimed_pickup()
        if trade_target != null and trade_target.has_method("buy"):
            trade_target.call("buy", player)
    if Input.is_action_just_pressed("restart"):
        get_tree().reload_current_scene()
