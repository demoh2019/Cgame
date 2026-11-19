extends Node3D
## First playable Days After slice: walk, explore, scavenge and survive.
## Geometry is built from primitives so the project needs no external assets.

const PLAYER_SCRIPT = preload("res://player.gd")
const PICKUP_SCRIPT = preload("res://pickup.gd")
const STATE_SCRIPT = preload("res://survival_state.gd")
const RESOURCE_SCRIPT = preload("res://resource_node.gd")
const ENEMY_SCRIPT = preload("res://enemy.gd")
const SAVE_SCRIPT = preload("res://save_game.gd")

var state = STATE_SCRIPT.new()
var player
var stats_label: Label
var prompt_label: Label
var status_label: Label
var progression_label: Label
var _save_notice: String = ""
var _save_notice_time: float = 0.0


func _ready() -> void:
    _install_inputs()
    _build_world()
    _spawn_player()
    _spawn_infected("InfectedScavenger", Vector3(4, 0.15, -12))
    _build_hud()


func _process(delta: float) -> void:
    if player == null:
        return
    state.tick(delta, player.is_sprinting)
    _save_notice_time = maxf(0.0, _save_notice_time - delta)
    player.sprint_allowed = state.stamina > 0.1 and not state.dead
    player.can_move = not state.dead
    if stats_label != null:
        stats_label.text = "DAY 1 | HP %d HUNGER %d THIRST %d STAMINA %d\nFOOD %d WATER %d SCRAP %d WOOD %d STONE %d FIBER %d" % [
            int(state.health), int(state.hunger), int(state.thirst), int(state.stamina),
            int(state.inventory["food"]), int(state.inventory["water"]), int(state.inventory["scrap"]),
            int(state.inventory["wood"]), int(state.inventory["stone"]), int(state.inventory["fiber"])
        ]
    if progression_label != null:
        var weapon: String = state.equipped["weapon"]
        var armor: String = state.equipped["armor"]
        progression_label.text = "GATHERING Lv.%d | CRAFTING Lv.%d | WEAPON %s | ARMOR %s\nCRAFTED: Spear %d Coat %d Bandage %d" % [
            state.skill_level("gathering"), state.skill_level("crafting"),
            weapon if not weapon.is_empty() else "none", armor if not armor.is_empty() else "none",
            int(state.inventory["makeshift_spear"]), int(state.inventory["padded_coat"]), int(state.inventory["bandage"])
        ]
    if prompt_label != null:
        var focus = player.get_focused_pickup()
        prompt_label.text = "[E] Gather %s" % str(focus.get("resource_type")).capitalize() if focus != null else ""
    if status_label != null:
        var help_text := "YOU DID NOT SURVIVE" if state.dead else "WASD move / Shift sprint / E gather / Left click attack / Esc mouse\n1 Eat  2 Drink  3 Craft spear  4 Craft coat  5 Craft bandage\n6 Equip spear  7 Equip coat  8 Use bandage  |  F5 Save  F9 Load"
        if _save_notice_time > 0.0:
            help_text += "\n" + _save_notice
        status_label.text = help_text


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("use_food"):
        state.use_resource("food")
    elif event.is_action_pressed("use_water"):
        state.use_resource("water")
    elif event.is_action_pressed("craft_spear"):
        state.craft("makeshift_spear")
    elif event.is_action_pressed("craft_coat"):
        state.craft("padded_coat")
    elif event.is_action_pressed("craft_bandage"):
        state.craft("bandage")
    elif event.is_action_pressed("equip_spear"):
        state.equip("makeshift_spear")
    elif event.is_action_pressed("equip_coat"):
        state.equip("padded_coat")
    elif event.is_action_pressed("use_bandage"):
        state.use_resource("bandage")
    elif event.is_action_pressed("save_game"):
        save_game()
    elif event.is_action_pressed("load_game"):
        load_game()
    elif event.is_action_pressed("release_mouse"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if DisplayServer.get_name() != "headless":
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_interact(target: Node) -> void:
    if target == null or not target.has_method("collect") or target.is_queued_for_deletion():
        return
    var result: Dictionary = target.call("collect")
    if result.has("type") and result.has("amount"):
        if bool(result.get("gathering", false)):
            state.gather(str(result["type"]), int(result["amount"]))
        else:
            state.add_resource(str(result["type"]), int(result["amount"]))


func _on_attack(target: Node) -> void:
    if target != null and not target.is_queued_for_deletion() and target.has_method("take_damage"):
        target.call("take_damage", state.get_attack_damage())


func _on_enemy_attack(raw_damage: float) -> void:
    state.apply_damage(raw_damage)


## Game saves use native FileAccess, with whole-snapshot validation and atomic replace.
func save_game(path: String = "") -> bool:
    var checkpoint_path: String = SAVE_SCRIPT.DEFAULT_PATH if path.is_empty() else path
    var success: bool = SAVE_SCRIPT.save(self, checkpoint_path)
    _save_notice = "CHECKPOINT SAVED" if success else "SAVE FAILED"
    _save_notice_time = 4.0
    return success


func load_game(path: String = "") -> bool:
    var checkpoint_path: String = SAVE_SCRIPT.DEFAULT_PATH if path.is_empty() else path
    var success: bool = SAVE_SCRIPT.load(self, checkpoint_path)
    _save_notice = "CHECKPOINT RESTORED" if success else "NO VALID CHECKPOINT"
    _save_notice_time = 4.0
    return success


func _install_inputs() -> void:
    _bind_key("move_forward", KEY_W)
    _bind_key("move_back", KEY_S)
    _bind_key("move_left", KEY_A)
    _bind_key("move_right", KEY_D)
    _bind_key("sprint", KEY_SHIFT)
    _bind_key("interact", KEY_E)
    _bind_key("use_food", KEY_1)
    _bind_key("use_water", KEY_2)
    _bind_key("release_mouse", KEY_ESCAPE)
    _bind_key("craft_spear", KEY_3)
    _bind_key("craft_coat", KEY_4)
    _bind_key("craft_bandage", KEY_5)
    _bind_key("equip_spear", KEY_6)
    _bind_key("equip_coat", KEY_7)
    _bind_key("use_bandage", KEY_8)
    _bind_key("save_game", KEY_F5)
    _bind_key("load_game", KEY_F9)
    if not InputMap.has_action("attack"):
        InputMap.add_action("attack")
        var attack_key := InputEventMouseButton.new()
        attack_key.button_index = MOUSE_BUTTON_LEFT
        InputMap.action_add_event("attack", attack_key)


func _bind_key(action: StringName, key: Key) -> void:
    if InputMap.has_action(action):
        return
    InputMap.add_action(action)
    var input := InputEventKey.new()
    input.physical_keycode = key
    InputMap.action_add_event(action, input)


func _build_world() -> void:
    var environment_node := WorldEnvironment.new()
    environment_node.name = "Atmosphere"
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.17, 0.22, 0.26)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.58, 0.63, 0.7)
    environment.ambient_light_energy = 0.8
    environment_node.environment = environment
    add_child(environment_node)

    var sun := DirectionalLight3D.new()
    sun.name = "OvercastSun"
    sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
    sun.light_energy = 0.9
    sun.shadow_enabled = true
    add_child(sun)

    _create_solid("Ground", Vector3(0, -0.5, 0), Vector3(64, 1, 64), Color(0.32, 0.34, 0.28))
    _create_solid("RuinWest", Vector3(-8, 1.7, -11), Vector3(1.0, 3.4, 12.0), Color(0.41, 0.43, 0.43))
    _create_solid("RuinNorth", Vector3(-2, 1.7, -16), Vector3(13.0, 3.4, 1.0), Color(0.4, 0.4, 0.39))
    _create_solid("RuinEast", Vector3(8, 1.3, -11), Vector3(1.2, 2.6, 9.0), Color(0.38, 0.39, 0.39))
    _create_solid("Barricade", Vector3(6, 0.7, 0), Vector3(4, 1.4, 0.9), Color(0.45, 0.31, 0.22))
    _create_solid("SupplyCrate", Vector3(-3, 0.5, -6), Vector3(1, 1, 1), Color(0.37, 0.26, 0.17))
    _create_solid("ScrapContainer", Vector3(10, 0.8, 5), Vector3(2.6, 1.6, 4), Color(0.27, 0.34, 0.38))

    _create_pickup("WaterBottle", "water", 1, Vector3(-2, 0.6, -3), Color(0.23, 0.61, 0.88))
    _create_pickup("FoodRation", "food", 1, Vector3(2, 0.6, -4), Color(0.52, 0.78, 0.27))
    _create_pickup("ScrapMetal", "scrap", 2, Vector3(3.5, 0.6, -8), Color(0.82, 0.64, 0.37))
    _create_pickup("SecondWaterBottle", "water", 1, Vector3(-5, 0.6, -12), Color(0.23, 0.61, 0.88))
    _create_resource("FallenTimber", "wood", 3, Vector3(-5, 0.7, 1), Color(0.52, 0.35, 0.17))
    _create_resource("TreeStump", "wood", 3, Vector3(9, 0.7, -4), Color(0.52, 0.35, 0.17))
    _create_resource("DryGrass", "fiber", 4, Vector3(2, 0.7, -9), Color(0.65, 0.75, 0.23))
    _create_resource("WildFibers", "fiber", 3, Vector3(-6, 0.7, -8), Color(0.65, 0.75, 0.23))
    _create_resource("RockDeposit", "stone", 4, Vector3(11, 0.7, 6), Color(0.56, 0.59, 0.58))


func _create_solid(name_text: String, center: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = name_text
    body.position = center
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    var mesh := MeshInstance3D.new()
    var box_mesh := BoxMesh.new()
    box_mesh.size = size
    mesh.mesh = box_mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 1.0
    mesh.material_override = material
    body.add_child(mesh)
    add_child(body)


func _create_pickup(name_text: String, kind: String, amount: int, location: Vector3, color: Color) -> void:
    var item = Area3D.new()
    item.name = name_text
    item.set_script(PICKUP_SCRIPT)
    item.set("resource_type", kind)
    item.set("amount", amount)
    item.position = location
    item.collision_layer = 2
    item.collision_mask = 0
    item.add_to_group("days_after_pickup")
    var collider := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 0.5
    collider.shape = shape
    item.add_child(collider)
    var mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.3
    sphere.height = 0.6
    mesh.mesh = sphere
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = 0.2
    mesh.material_override = material
    item.add_child(mesh)
    add_child(item)


func _create_resource(name_text: String, kind: String, charges: int, location: Vector3, color: Color) -> void:
    var node := Area3D.new()
    node.name = name_text
    node.set_script(RESOURCE_SCRIPT)
    node.set("resource_type", kind)
    node.set("charges", charges)
    node.position = location
    node.collision_layer = 2
    node.collision_mask = 0
    node.add_to_group("days_after_resource")
    var collider := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 0.65
    collider.shape = shape
    node.add_child(collider)
    var mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.47
    sphere.height = 0.94
    mesh.mesh = sphere
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    mesh.material_override = material
    node.add_child(mesh)
    add_child(node)


func _spawn_infected(name_text: String, location: Vector3) -> void:
    var infected := CharacterBody3D.new()
    infected.name = name_text
    infected.position = location
    infected.set_script(ENEMY_SCRIPT)
    infected.set("target", player)
    infected.add_to_group("days_after_enemy")
    var collider := CollisionShape3D.new()
    collider.position.y = 0.9
    var shape := CapsuleShape3D.new()
    shape.radius = 0.37
    shape.height = 1.8
    collider.shape = shape
    infected.add_child(collider)
    var mesh := MeshInstance3D.new()
    mesh.position.y = 0.9
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.37
    capsule.height = 1.8
    mesh.mesh = capsule
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.41, 0.52, 0.39)
    mesh.material_override = material
    infected.add_child(mesh)
    add_child(infected)
    infected.connect("attacked_player", Callable(self, "_on_enemy_attack"))


func _spawn_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Survivor"
    player.set_script(PLAYER_SCRIPT)
    player.position = Vector3(0, 0.15, 3)
    var collider := CollisionShape3D.new()
    collider.position.y = 0.9
    var shape := CapsuleShape3D.new()
    shape.radius = 0.34
    shape.height = 1.8
    collider.shape = shape
    player.add_child(collider)
    var camera := Camera3D.new()
    camera.name = "Camera3D"
    camera.position.y = 1.56
    camera.current = true
    player.add_child(camera)
    var ray := RayCast3D.new()
    ray.name = "InteractionRay"
    ray.target_position = Vector3(0, 0, -3.2)
    ray.collide_with_areas = true
    ray.collision_mask = 3
    ray.enabled = true
    camera.add_child(ray)
    add_child(player)
    player.interact_requested.connect(_on_interact)
    player.attack_requested.connect(_on_attack)


func _build_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "HUD"
    add_child(canvas)
    stats_label = Label.new()
    stats_label.name = "Stats"
    stats_label.position = Vector2(22, 18)
    stats_label.add_theme_font_size_override("font_size", 19)
    canvas.add_child(stats_label)
    status_label = Label.new()
    status_label.name = "Status"
    progression_label = Label.new()
    progression_label.name = "Progression"
    progression_label.position = Vector2(22, 94)
    progression_label.add_theme_font_size_override("font_size", 16)
    canvas.add_child(progression_label)
    status_label.position = Vector2(22, 163)
    status_label.add_theme_font_size_override("font_size", 16)
    canvas.add_child(status_label)
    prompt_label = Label.new()
    prompt_label.name = "InteractionPrompt"
    prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    prompt_label.position = Vector2(-80, -90)
    prompt_label.add_theme_font_size_override("font_size", 24)
    canvas.add_child(prompt_label)
    var crosshair := Label.new()
    crosshair.name = "Crosshair"
    crosshair.text = "+"
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.position = Vector2(-5, -18)
    crosshair.add_theme_font_size_override("font_size", 25)
    canvas.add_child(crosshair)
