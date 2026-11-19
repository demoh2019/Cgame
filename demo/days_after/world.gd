extends Node3D
## Procedural prototype map: no imported assets or engine-specific plugins required.

const Player = preload("res://player.gd")
const LootPickup = preload("res://loot_pickup.gd")
const ResourceNode = preload("res://resource_node.gd")
const DAY_DURATION_SECONDS := 600.0

var _player
var _sun: DirectionalLight3D
var _environment: Environment
var _readout: Label
var _prompt: Label
var _elapsed := 0.0


func _ready() -> void:
    _setup_environment()
    _static_block("Ground", Vector3(0, -0.5, 0), Vector3(70, 1, 70), Color(0.22, 0.29, 0.2))
    _build_ruins()
    _build_supplies()
    _build_resources()
    _player = Player.new()
    _player.position = Vector3(0.0, 1.3, 5.0)
    add_child(_player)
    _create_hud()


func _setup_environment() -> void:
    var world := WorldEnvironment.new()
    _environment = Environment.new()
    _environment.background_mode = Environment.BG_COLOR
    _environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    _environment.ambient_light_color = Color(0.74, 0.8, 1.0)
    world.environment = _environment
    add_child(world)
    _sun = DirectionalLight3D.new()
    _sun.shadow_enabled = true
    add_child(_sun)


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.92
    return material


func _static_block(block_name: String, position_3d: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = block_name
    body.position = position_3d
    var shape := BoxShape3D.new()
    shape.size = size
    var collision := CollisionShape3D.new()
    collision.shape = shape
    body.add_child(collision)
    var mesh := BoxMesh.new()
    mesh.size = size
    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    visual.material_override = _material(color)
    body.add_child(visual)
    add_child(body)


func _build_ruins() -> void:
    var concrete := Color(0.38, 0.39, 0.37)
    _static_block("RuinWest", Vector3(-7, 1.8, -9), Vector3(0.8, 3.6, 9), concrete)
    _static_block("RuinNorth", Vector3(-3, 1.8, -13), Vector3(9, 3.6, 0.8), concrete)
    _static_block("RuinEast", Vector3(2, 1.1, -10), Vector3(0.8, 2.2, 5), concrete)
    _static_block("Shelter", Vector3(10, 1.2, 2), Vector3(5, 2.4, 5), Color(0.29, 0.28, 0.26))
    for i in range(6):
        var x := -11.0 + float(i) * 3.5
        _static_block("Debris_%d" % i, Vector3(x, 0.45, -4.0 - float(i % 2) * 2.0), Vector3(1.2, 0.9, 1.2), Color(0.42, 0.37, 0.32))
    for i in range(3):
        var crate := RigidBody3D.new()
        crate.name = "LooseCrate_%d" % i
        crate.position = Vector3(-4.0 + float(i) * 1.2, 3.0 + float(i), 0.0)
        var shape := BoxShape3D.new()
        shape.size = Vector3(0.8, 0.8, 0.8)
        var collision := CollisionShape3D.new()
        collision.shape = shape
        crate.add_child(collision)
        var visual := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = shape.size
        visual.mesh = mesh
        visual.material_override = _material(Color(0.46, 0.27, 0.13))
        crate.add_child(visual)
        add_child(crate)


func _build_supplies() -> void:
    _supply("water", 2, Vector3(1.0, 0.3, 2.0))
    _supply("food", 2, Vector3(-1.6, 0.3, 1.0))
    _supply("water", 1, Vector3(-4.0, 0.3, -7.0))
    _supply("food", 1, Vector3(3.0, 0.3, -11.0))


func _supply(kind: String, amount: int, at: Vector3) -> void:
    var pickup := LootPickup.new()
    pickup.setup(kind, amount)
    pickup.position = at
    add_child(pickup)


func _build_resources() -> void:
    _resource("wood", 3, Vector3(6.0, 0.6, -2.0))
    _resource("wood", 3, Vector3(8.0, 0.6, -7.0))
    _resource("fiber", 3, Vector3(-3.0, 0.6, 3.0))
    _resource("fiber", 3, Vector3(-11.0, 0.6, 3.0))
    _resource("scrap", 3, Vector3(3.0, 0.6, -6.0))
    _resource("scrap", 3, Vector3(-3.0, 0.6, -10.0))


func _resource(kind: String, units: int, at: Vector3) -> void:
    var node := ResourceNode.new()
    node.setup(kind, units)
    node.position = at
    add_child(node)


func _create_hud() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var panel := PanelContainer.new()
    panel.position = Vector2(14, 14)
    panel.custom_minimum_size = Vector2(320, 0)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(panel)
    var layout := VBoxContainer.new()
    panel.add_child(layout)
    var title := Label.new()
    title.text = "DAYS AFTER × ALBION  |  Cgame prototype"
    layout.add_child(title)
    _readout = Label.new()
    layout.add_child(_readout)
    var controls := Label.new()
    controls.text = "WASD move | Shift sprint | E loot/gather | Esc cursor\n1 eat | 2 drink | 3 bandage | 7 medkit\n4 craft bandage | 5 craft hatchet | 6 craft medkit (Lv 2)"
    layout.add_child(controls)
    _prompt = Label.new()
    layout.add_child(_prompt)


func _process(delta: float) -> void:
    _elapsed += maxf(delta, 0.0)
    var absolute_hours := 9.0 + _elapsed * 24.0 / DAY_DURATION_SECONDS
    var hour := fposmod(absolute_hours, 24.0)
    var day := 1 + int(floor(absolute_hours / 24.0))
    var daylight := maxf(0.0, sin((hour - 6.0) / 24.0 * TAU))
    _sun.rotation_degrees = Vector3(-8.0 - 75.0 * daylight, -35.0, 0.0)
    _sun.light_energy = 0.04 + daylight * 1.25
    _environment.ambient_light_energy = 0.18 + daylight * 0.72
    _environment.background_color = Color(0.015, 0.02, 0.05).lerp(Color(0.23, 0.36, 0.49), daylight)
    var stats = _player.state
    _readout.text = "Day %d  %02d:%02d\nHP %d | Hunger %d | Water %d | Stamina %d\nFood %d | Water %d | Wood %d | Fiber %d | Scrap %d\nBandage %d | Hatchet %d | Medkit %d\nGathering Lv %d (%d XP) | Crafting Lv %d (%d XP)" % [
        day, int(hour), int((hour - floor(hour)) * 60.0),
        int(stats.health), int(stats.hunger), int(stats.thirst), int(stats.stamina),
        int(_player.inventory["food"]), int(_player.inventory["water"]),
        int(_player.inventory["wood"]), int(_player.inventory["fiber"]), int(_player.inventory["scrap"]),
        int(_player.inventory["bandage"]), int(_player.inventory["hatchet"]), int(_player.inventory["medkit"]),
        _player.progression.skill_level("gathering"), int(_player.progression.experience["gathering"]),
        _player.progression.skill_level("crafting"), int(_player.progression.experience["crafting"])
    ]
    var caption := _player.target_caption()
    _prompt.text = "E: gather / collect " + caption if not caption.is_empty() else "Explore, scavenge, craft, survive."
