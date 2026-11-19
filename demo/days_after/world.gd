extends Node3D
## Self-contained playable Days After vertical slice; no imported assets needed.

const PLAYER_SCRIPT = preload("res://player.gd")
const ZOMBIE_SCRIPT = preload("res://zombie.gd")
const PICKUP_SCRIPT = preload("res://pickup.gd")
const DAY_SECONDS := 240.0

var player
var hud_label: Label
var notice_label: Label
var sun: DirectionalLight3D
var elapsed_day := DAY_SECONDS * 0.33
var day_number := 1
var kills := 0
var total_zombies := 0
var notice_timer := 0.0


func _ready() -> void:
    _build_world()
    _build_player()
    _build_enemies()
    _build_supplies()
    _build_hud()
    _show_notice("Survive. Find supplies. Clear the infected.", 5.0)


func _process(delta: float) -> void:
    elapsed_day += delta
    if elapsed_day >= DAY_SECONDS:
        elapsed_day = fmod(elapsed_day, DAY_SECONDS)
        day_number += 1
        _show_notice("Day %d — still alive." % day_number, 4.0)

    var phase: float = elapsed_day / DAY_SECONDS
    var brightness: float = maxf(0.0, sin(phase * TAU))
    sun.light_energy = 0.15 + brightness * 1.05

    if notice_timer > 0.0:
        notice_timer -= delta
        if notice_timer <= 0.0:
            notice_label.text = ""
    _refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E and not player.dead:
            collect_nearest_loot()
        elif event.keycode == KEY_R and player.dead:
            get_tree().reload_current_scene()


func _build_world() -> void:
    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.30, 0.39, 0.43)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.63, 0.72, 0.78)
    environment.ambient_light_energy = 0.42
    environment_node.environment = environment
    add_child(environment_node)

    sun = DirectionalLight3D.new()
    sun.name = "DayNightSun"
    sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
    add_child(sun)

    _build_obstacle("Ground", Vector3(0.0, -0.5, 0.0), Vector3(64.0, 1.0, 64.0), Color(0.25, 0.33, 0.24))
    _build_obstacle("Shelter", Vector3(-9.0, 2.5, -8.0), Vector3(7.0, 5.0, 6.0), Color(0.40, 0.38, 0.34))
    _build_obstacle("Warehouse", Vector3(11.0, 2.5, 10.0), Vector3(9.0, 5.0, 7.0), Color(0.32, 0.37, 0.41))
    _build_obstacle("AbandonedCar", Vector3(9.0, 0.8, -7.0), Vector3(3.7, 1.6, 1.8), Color(0.45, 0.24, 0.22))
    _build_obstacle("Barricade", Vector3(-12.0, 0.6, 8.0), Vector3(5.0, 1.2, 1.2), Color(0.43, 0.36, 0.26))
    _build_obstacle("Crate", Vector3(4.0, 0.7, 6.0), Vector3(1.4, 1.4, 1.4), Color(0.51, 0.39, 0.25))

    for i in range(8):
        var x: float = -26.0 + float(i) * 6.5
        _build_obstacle("NorthFence%d" % i, Vector3(x, 1.2, -29.0), Vector3(5.5, 2.4, 0.4), Color(0.35, 0.35, 0.34))


func _build_obstacle(object_name: String, center: Vector3, size: Vector3, color: Color) -> void:
    var obstacle := StaticBody3D.new()
    obstacle.name = object_name
    obstacle.position = center
    obstacle.collision_layer = 1
    obstacle.collision_mask = 0

    var shape := BoxShape3D.new()
    shape.size = size
    var collider := CollisionShape3D.new()
    collider.shape = shape
    obstacle.add_child(collider)

    var mesh := BoxMesh.new()
    mesh.size = size
    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    visual.material_override = material
    obstacle.add_child(visual)
    add_child(obstacle)


func _build_player() -> void:
    player = PLAYER_SCRIPT.new()
    player.name = "Player"
    add_child(player)
    player.position = Vector3(0.0, 0.1, 0.0)
    player.attacked.connect(_on_player_attacked)
    player.died.connect(_on_player_died)


func _build_enemies() -> void:
    var locations: Array[Vector3] = [
        Vector3(-15.0, 0.2, -13.0),
        Vector3(13.0, 0.2, -13.0),
        Vector3(-7.0, 0.2, 13.0),
        Vector3(5.0, 0.2, 17.0),
        Vector3(-19.0, 0.2, 6.0),
        Vector3(17.0, 0.2, 1.0)
    ]
    total_zombies = locations.size()
    for spawn_position in locations:
        var zombie = ZOMBIE_SCRIPT.new()
        zombie.target = player
        zombie.died.connect(_on_zombie_died)
        add_child(zombie)
        zombie.global_position = spawn_position


func _build_supplies() -> void:
    spawn_pickup("food", 1, Vector3(2.0, 0.6, -1.0))
    spawn_pickup("water", 1, Vector3(-2.0, 0.6, 1.0))
    spawn_pickup("scrap", 2, Vector3(6.0, 0.6, -7.0))
    spawn_pickup("food", 2, Vector3(-14.0, 0.6, 2.0))
    spawn_pickup("water", 2, Vector3(14.0, 0.6, 5.0))
    spawn_pickup("scrap", 3, Vector3(2.0, 0.6, 13.0))


func spawn_pickup(item_type: String, amount: int, at_position: Vector3) -> Node3D:
    var pickup = PICKUP_SCRIPT.new()
    pickup.configure(item_type, amount)
    add_child(pickup)
    pickup.global_position = at_position
    return pickup


func collect_nearest_loot() -> bool:
    var nearest
    var best_distance := 2.25
    for loot in get_tree().get_nodes_in_group("loot"):
        if loot.is_queued_for_deletion():
            continue
        var distance: float = player.global_position.distance_to(loot.global_position)
        if distance < best_distance:
            nearest = loot
            best_distance = distance
    if nearest == null:
        _show_notice("No supplies within reach.", 2.0)
        return false
    player.add_item(nearest.item_type, nearest.quantity)
    _show_notice("Picked up %s x%d" % [nearest.item_type, nearest.quantity], 2.5)
    nearest.queue_free()
    return true


func _on_player_attacked(damage: float, reach: float) -> void:
    var nearest
    var best_distance: float = reach
    for zombie in get_tree().get_nodes_in_group("zombies"):
        if zombie.is_queued_for_deletion():
            continue
        var distance: float = player.global_position.distance_to(zombie.global_position)
        if distance < best_distance:
            nearest = zombie
            best_distance = distance
    if nearest != null:
        nearest.take_damage(damage)


func _on_zombie_died() -> void:
    kills += 1
    if kills == total_zombies:
        _show_notice("Area secured! Survive another night.", 8.0)


func _on_player_died() -> void:
    _show_notice("YOU DIED — press R to restart.", 3600.0)


func _build_hud() -> void:
    var overlay := CanvasLayer.new()
    overlay.name = "SurvivalHUD"
    add_child(overlay)

    hud_label = Label.new()
    hud_label.name = "Status"
    hud_label.position = Vector2(18.0, 16.0)
    hud_label.add_theme_font_size_override("font_size", 20)
    overlay.add_child(hud_label)

    notice_label = Label.new()
    notice_label.name = "Notice"
    notice_label.position = Vector2(18.0, 201.0)
    notice_label.add_theme_font_size_override("font_size", 22)
    overlay.add_child(notice_label)
    _refresh_hud()


func _refresh_hud() -> void:
    if hud_label == null or player == null:
        return
    var hour: int = int(floor(elapsed_day / DAY_SECONDS * 24.0))
    var minute: int = int(floor(fmod(elapsed_day / DAY_SECONDS * 1440.0, 60.0)))
    hud_label.text = (
        "DAYS AFTER  |  Day %d  %02d:%02d\n" +
        "HP %d   Food %d   Water %d   Stamina %d\n" +
        "Supplies: food %d  water %d  scrap %d   |   Infected %d/%d\n" +
        "WASD move  Shift run  Space/LMB attack  E loot  1 eat  2 drink"
    ) % [
        day_number, hour, minute,
        int(player.health), int(player.hunger), int(player.thirst), int(player.stamina),
        int(player.inventory.get("food", 0)), int(player.inventory.get("water", 0)),
        int(player.inventory.get("scrap", 0)), kills, total_zombies
    ]


func _show_notice(message: String, duration: float) -> void:
    if notice_label == null:
        return
    notice_label.text = message
    notice_timer = duration
