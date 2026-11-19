extends Node3D
## Days After-style survival loop plus Albion-style gathering and equipment.
## Prototype only: no network replication, persistence, guilds or trading yet.

const StateScript = preload("res://game_state.gd")
const PlayerScript = preload("res://player.gd")
const ZombieScript = preload("res://zombie.gd")

const GATHER_DISTANCE := 2.5
const ATTACK_DISTANCE := 2.4
const COLOR_GROUND := Color("#344a3e")
const RESOURCE_COLORS := {
    "wood": Color("#926d43"),
    "stone": Color("#858e99"),
    "fiber": Color("#6ebc77"),
    "herb": Color("#4cc6a1")
}

var state = StateScript.new()
var player
var follow_camera: Camera3D
var hud: Label
var hud_timer := 0.0
var status_message := "Explore the ruins and build a shelter."


func _ready() -> void:
    _create_environment()
    _create_player()
    _create_resources()
    _create_zombies()
    _create_hud()


func _process(delta: float) -> void:
    state.tick(delta)
    if state.health <= 0.0:
        player.active = false
        status_message = "You died. Press R to restart."
    follow_camera.global_position = player.global_position + Vector3(12.0, 17.0, 14.0)
    follow_camera.look_at(player.global_position + Vector3(0.0, 0.8, 0.0))
    hud_timer -= delta
    if hud_timer <= 0.0:
        hud_timer = 0.2
        _update_hud()


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.85
    return material


func _make_box(label: String, at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = label
    body.position = at
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    var visual := MeshInstance3D.new()
    visual.name = "Visual"
    var box_mesh := BoxMesh.new()
    box_mesh.size = size
    visual.mesh = box_mesh
    visual.material_override = _material(color)
    body.add_child(visual)
    add_child(body)
    return body


func _create_environment() -> void:
    var world := WorldEnvironment.new()
    world.name = "Sky"
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#8aa2a1")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#b7c5b9")
    world.environment = environment
    add_child(world)
    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
    add_child(sun)
    _make_box("Ground", Vector3(0.0, -0.4, 0.0), Vector3(80.0, 0.8, 80.0), COLOR_GROUND)
    for position in [Vector3(-10, 1.0, -7), Vector3(14, 1.0, 10), Vector3(-13, 1.0, 12)]:
        _make_box("RuinedWall", position, Vector3(5.0, 2.0, 0.7), Color("#666969"))
    follow_camera = Camera3D.new()
    follow_camera.name = "IsometricCamera"
    follow_camera.current = true
    follow_camera.fov = 52.0
    add_child(follow_camera)


func _create_player() -> void:
    player = PlayerScript.new()
    player.name = "Survivor"
    player.position = Vector3(0.0, 0.95, 0.0)
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.37
    shape.height = 1.8
    collider.shape = shape
    player.add_child(collider)
    var visual := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.37
    capsule.height = 1.8
    visual.mesh = capsule
    visual.material_override = _material(Color("#e0be84"))
    player.add_child(visual)
    add_child(player)


func _spawn_resource(kind: String, at: Vector3) -> void:
    var body := _make_box("Gather_" + kind, at, Vector3(0.85, 0.7, 0.85), RESOURCE_COLORS[kind])
    body.add_to_group("gatherable")
    body.set_meta("kind", kind)
    body.set_meta("remaining", 4)


func _create_resources() -> void:
    for at in [Vector3(-2, 0.35, -3), Vector3(3, 0.35, 1), Vector3(-7, 0.35, 4), Vector3(8, 0.35, -4)]:
        _spawn_resource("wood", at)
    for at in [Vector3(-4, 0.35, 2), Vector3(5, 0.35, -3), Vector3(9, 0.35, 5)]:
        _spawn_resource("stone", at)
    for at in [Vector3(2, 0.35, -4), Vector3(-3, 0.35, 7), Vector3(7, 0.35, 7)]:
        _spawn_resource("fiber", at)
    for at in [Vector3(-1, 0.35, 5), Vector3(4, 0.35, 6)]:
        _spawn_resource("herb", at)


func _spawn_zombie(at: Vector3) -> void:
    var zombie = ZombieScript.new()
    zombie.name = "Infected"
    zombie.position = at
    zombie.target = player
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.37
    shape.height = 1.8
    collider.shape = shape
    zombie.add_child(collider)
    var visual := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.37
    capsule.height = 1.8
    visual.mesh = capsule
    visual.material_override = _material(Color("#a9a87c"))
    zombie.add_child(visual)
    zombie.add_to_group("infected")
    add_child(zombie)


func _create_zombies() -> void:
    for at in [Vector3(-9, 0.95, -8), Vector3(10, 0.95, -9), Vector3(6, 0.95, 12)]:
        _spawn_zombie(at)


func _create_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(14, 14)
    layer.add_child(panel)
    var margin := MarginContainer.new()
    for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
        margin.add_theme_constant_override(side, 12)
    panel.add_child(margin)
    hud = Label.new()
    hud.name = "Status"
    margin.add_child(hud)
    _update_hud()


func _update_hud() -> void:
    var weapon := "Spear" if state.has_spear else "Hands"
    hud.text = "Cgame | SURVIVAL x SANDBOX (offline prototype)\n"
    hud.text += "HP: %d/100 | Hunger: %d/100 | Weapon: %s\n" % [int(state.health), int(state.hunger), weapon]
    hud.text += "Wood: %d | Stone: %d | Fiber: %d | Herb: %d | Scrap: %d\n" % [
        state.items["wood"], state.items["stone"], state.items["fiber"], state.items["herb"], state.items["scrap"]]
    hud.text += "Zombies left: %d\n" % get_tree().get_nodes_in_group("infected").size()
    hud.text += "WASD move | Shift sprint | E gather | Space attack\n"
    hud.text += "Q craft spear (2 wood, 1 stone) | H bandage (2 fiber, 1 herb)\n"
    hud.text += "F eat herb | B build barricade (3 wood, 2 stone) | R restart\n"
    hud.text += status_message


func _distance_flat(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _harvest() -> void:
    var nearest: StaticBody3D
    var distance := GATHER_DISTANCE
    for node in get_tree().get_nodes_in_group("gatherable"):
        if not is_instance_valid(node) or node.is_queued_for_deletion():
            continue
        var d := _distance_flat(player.global_position, node.global_position)
        if d < distance:
            nearest = node
            distance = d
    if nearest == null:
        status_message = "Move closer to a resource."
        return
    var kind := str(nearest.get_meta("kind"))
    state.add_item(kind)
    var remaining := int(nearest.get_meta("remaining")) - 1
    nearest.set_meta("remaining", remaining)
    if remaining <= 0:
        nearest.queue_free()
    else:
        nearest.get_node("Visual").scale *= 0.83
    status_message = "Gathered 1 %s." % kind


func _attack() -> void:
    var nearest
    var distance := ATTACK_DISTANCE
    for node in get_tree().get_nodes_in_group("infected"):
        if not is_instance_valid(node) or node.is_queued_for_deletion():
            continue
        var d := _distance_flat(player.global_position, node.global_position)
        if d < distance:
            nearest = node
            distance = d
    if nearest == null:
        status_message = "No enemy in range."
        return
    var damage := 26.0 if state.has_spear else 10.0
    if nearest.take_damage(damage):
        state.add_item("scrap")
        status_message = "Infected defeated! +1 scrap."
    else:
        status_message = "Hit infected for %d damage." % int(damage)


func _build() -> void:
    if not state.spend_recipe("barricade"):
        status_message = "Barricade requires 3 wood and 2 stone."
        return
    var pos: Vector3 = player.global_position + player.facing_direction() * 2.7
    pos.y = 0.7
    var barrier := _make_box("Barricade", pos, Vector3(2.0, 1.4, 0.6), Color("#76583d"))
    barrier.rotation.y = atan2(-player.facing_direction().x, -player.facing_direction().z)
    barrier.add_to_group("player_building")
    status_message = "Barricade built (physical obstacle)."


func receive_zombie_hit(damage: float) -> void:
    if state.health <= 0.0:
        return
    state.apply_damage(damage)
    status_message = "An infected hit you!"


func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    if not event.pressed or event.echo:
        return
    if event.physical_keycode == KEY_R:
        get_tree().reload_current_scene()
        return
    if state.health <= 0.0:
        return
    match event.physical_keycode:
        KEY_E:
            _harvest()
        KEY_SPACE:
            _attack()
        KEY_Q:
            if state.craft_spear():
                status_message = "Spear crafted. Melee damage increased."
            else:
                status_message = "Need 2 wood + 1 stone (or spear already equipped)."
        KEY_H:
            if state.spend_recipe("bandage"):
                state.heal(35.0)
                status_message = "Bandage used: +35 HP."
            else:
                status_message = "Bandage requires 2 fiber + 1 herb."
        KEY_F:
            if state.eat_herb():
                status_message = "Ate herb: +22 hunger."
            else:
                status_message = "Need a herb (and missing hunger)."
        KEY_B:
            _build()
