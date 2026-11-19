extends Node3D

## First playable Days After slice: one small scavenging area. All scenery
## uses procedural Godot primitives so the demo has no external asset dependencies.

const PLAYER_SCRIPT = preload("res://player.gd")
const PICKUP_SCRIPT = preload("res://pickup.gd")
const RESOURCE_SCRIPT = preload("res://resource_node.gd")
const ZOMBIE_SCRIPT = preload("res://zombie.gd")
const STASH_SCRIPT = preload("res://stash.gd")
const WORLD_SAVE = preload("res://world_state.gd")
const CONSTRUCTION_SCRIPT = preload("res://construction.gd")
const STASH_ITEMS := [
    "wood_t1", "stone_t1", "fiber_t1", "wood_t2", "stone_t2", "fiber_t2",
    "food", "water", "field_bandage", "reinforced_bandage",
    "scavenger_tool", "rusty_spear", "reinforced_spear", "scrap_vest"
]

var player
var hud_label: Label
var prompt_label: Label
var infected_kills: int = 0
var infected_total: int = 0
var construction: Node3D
var shelter_stash: Area3D
var stash_open := false
var stash_selected := 0


func _ready() -> void:
    _configure_controls()
    _build_world()
    _build_player()
    _build_pickups()
    _build_resources()
    _build_stash()
    _build_construction()
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
    for candidate_node in get_tree().get_nodes_in_group("infected"):
        var candidate := candidate_node as Node3D
        if candidate == null or candidate.is_queued_for_deletion():
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
    player.last_message = "Заражённый уничтожен! Опыт боя +25."




func _build_construction() -> void:
    construction = CONSTRUCTION_SCRIPT.new() as Node3D
    construction.name = "Construction"
    add_child(construction)


func _build_stash() -> void:
    shelter_stash = STASH_SCRIPT.new() as Area3D
    shelter_stash.name = "ShelterStash"
    shelter_stash.position = Vector3(2.0, 1.0, 9.5)
    add_child(shelter_stash)


func toggle_stash(stash: Node) -> void:
    if stash != shelter_stash or player.health <= 0.0:
        return
    if player.global_position.distance_to(shelter_stash.global_position) > 3.2:
        return
    stash_open = not stash_open
    player.last_message = "Склад открыт. Tab: предмет, G: положить, H: забрать." if stash_open else "Склад закрыт."


func _unhandled_input(event: InputEvent) -> void:
    var key_event := event as InputEventKey
    if key_event == null or not key_event.pressed or key_event.echo:
        return
    match key_event.keycode:
        KEY_F6:
            player.last_message = "Убежище и герой сохранены." if WORLD_SAVE.save_world(self) else "Не удалось сохранить мир."
        KEY_F10:
            stash_open = false
            player.last_message = "Убежище и герой загружены." if WORLD_SAVE.load_world(self) else "Нет корректного сохранения мира."
        KEY_ESCAPE:
            stash_open = false
        KEY_B:
            if not stash_open:
                var built := bool(construction.call("build_nearest", player))
                player.last_message = "Баррикада построена." if built else "Нужно 2 дерева T1, 1 камень T1 и свободная площадка рядом."
        KEY_N:
            if not stash_open:
                var repaired := bool(construction.call("repair_nearest", player))
                player.last_message = "Баррикада отремонтирована." if repaired else "Для ремонта нужны древесина T1 и повреждённая баррикада рядом."
        KEY_TAB:
            if stash_open:
                stash_selected = (stash_selected + 1) % STASH_ITEMS.size()
                get_viewport().set_input_as_handled()
        KEY_G:
            if stash_open:
                _transfer_stash(true)
        KEY_H:
            if stash_open:
                _transfer_stash(false)


func _transfer_stash(deposit_item: bool) -> void:
    if not stash_open or player.health <= 0.0:
        return
    if player.global_position.distance_to(shelter_stash.global_position) > 3.2:
        stash_open = false
        return
    var item_id: String = STASH_ITEMS[stash_selected]
    var successful: bool = bool(shelter_stash.call("deposit", player, item_id, 1)) if deposit_item else bool(shelter_stash.call("withdraw", player, item_id, 1))
    player.last_message = (
        ("Положено: " if deposit_item else "Забрано: ") + item_id
        if successful else "Операция невозможна: " + item_id
    )


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
        "Esc мышь | ЛКМ захват мыши | R перезапуск"
    column.add_child(help_label)

    prompt_label = Label.new()
    prompt_label.position = Vector2(18, 315)
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
        "Заражённые: %d/%d | Боевой опыт %d\n" % [
            infected_kills, infected_total, player.combat_xp
        ] +
        "F5/F9 герой | F6/F10 мир | B строить | N ремонт\n" +
        "Оборона убежища: %d/%d баррикад\n" % [
            int(construction.call("get_built_count")),
            CONSTRUCTION_SCRIPT.SLOT_POSITIONS.size()
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
    if stash_open:
        if player.global_position.distance_to(shelter_stash.global_position) > 3.2 or player.health <= 0.0:
            stash_open = false
        else:
            var item_id: String = STASH_ITEMS[stash_selected]
            prompt_label.text = (
                "СКЛАД УБЕЖИЩА | Tab: предмет | G: +1 | H: -1 | Esc: закрыть\n" +
                "%s   Рюкзак: %d   Склад: %d" % [
                    item_id, player.get_item_count(item_id),
                    int(shelter_stash.call("get_storage_count", item_id))
                ]
            )
    if Input.is_action_just_pressed("restart"):
        get_tree().reload_current_scene()
