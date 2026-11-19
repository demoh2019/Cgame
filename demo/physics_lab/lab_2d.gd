extends Node2D
## Independent 2D physics showcase. WASD pans the camera; nothing here uses
## external textures or addons.

const LAB_3D := "res://lab_3d.tscn"
const WALKER = preload("res://walker_2d.gd")
const INTERACTIVE_ENV_2D = preload("res://environment_2d.gd")

var _camera: Camera2D
var _stats: Label
var _event_label: Label
var _timer := 0.0
var _hits := 0
var _projectile_count := 0
var _shape_cast: ShapeCast2D


func _ready() -> void:
    _make_environment()
    _make_stacks()
    _make_slopes()
    _make_chains()
    _make_springs_and_areas()
    _make_ccd()
    _make_character()
    _make_camera()
    _make_ui()
    var interactions = INTERACTIVE_ENV_2D.new()
    interactions.name = "Environment2D"
    add_child(interactions)
    interactions.setup()


func _rect_vertices(size: Vector2) -> PackedVector2Array:
    var half := size * 0.5
    return PackedVector2Array([
        Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
        Vector2(half.x, half.y), Vector2(-half.x, half.y)
    ])


func _attach_rect(body: CollisionObject2D, size: Vector2, color: Color) -> void:
    var shape_node := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = size
    shape_node.shape = shape
    body.add_child(shape_node)
    var visual := Polygon2D.new()
    visual.polygon = _rect_vertices(size)
    visual.color = color
    body.add_child(visual)


func _static_rect(name: String, pos: Vector2, size: Vector2, color: Color, angle := 0.0) -> StaticBody2D:
    var body := StaticBody2D.new()
    body.name = name
    body.position = pos
    body.rotation = angle
    _attach_rect(body, size, color)
    add_child(body)
    return body


func _rigid_rect(pos: Vector2, size: Vector2, color: Color, mass := 1.0) -> RigidBody2D:
    var body := RigidBody2D.new()
    body.name = "DynamicRect2D"
    body.position = pos
    body.mass = mass
    _attach_rect(body, size, color)
    add_child(body)
    body.add_to_group("demo_dynamic_2d")
    return body


func _rigid_circle(pos: Vector2, radius: float, color: Color, mass := 1.0, ccd := false) -> RigidBody2D:
    var body := RigidBody2D.new()
    body.name = "DynamicCircle2D"
    body.position = pos
    body.mass = mass
    if ccd:
        body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
    var hitbox := CollisionShape2D.new()
    var shape := CircleShape2D.new()
    shape.radius = radius
    hitbox.shape = shape
    body.add_child(hitbox)
    var visual := Polygon2D.new()
    var vertices := PackedVector2Array()
    for i in range(28):
        vertices.append(Vector2.RIGHT.rotated(TAU * float(i) / 28.0) * radius)
    visual.polygon = vertices
    visual.color = color
    body.add_child(visual)
    add_child(body)
    body.add_to_group("demo_dynamic_2d")
    return body


func _station_label(pos: Vector2, caption: String) -> void:
    var label := Label.new()
    label.text = caption
    label.position = pos
    label.add_theme_font_size_override("font_size", 24)
    label.modulate = Color("#ecf0ff")
    add_child(label)


func _make_environment() -> void:
    var bg := Polygon2D.new()
    bg.polygon = _rect_vertices(Vector2(2400, 1150))
    bg.position = Vector2(0, 0)
    bg.color = Color("#121b29")
    bg.z_index = -5
    add_child(bg)
    _static_rect("2D Ground", Vector2(0, 420), Vector2(2300, 80), Color("#455c72"))
    _static_rect("West Boundary", Vector2(-1150, 0), Vector2(25, 1000), Color("#455c72"))
    _static_rect("East Boundary", Vector2(1150, 0), Vector2(25, 1000), Color("#455c72"))
    for station in range(5):
        var x := -800.0 + 400.0 * station
        var pad := Polygon2D.new()
        pad.polygon = _rect_vertices(Vector2(365, 12))
        pad.position = Vector2(x, 367)
        pad.color = Color.from_hsv(0.55 + station * 0.11, 0.26, 0.5)
        add_child(pad)
    _station_label(Vector2(-920, -440), "01  RigidBody2D / collisions")
    _station_label(Vector2(-520, -440), "02  Slopes / friction")
    _station_label(Vector2(-120, -440), "03  PinJoint2D / chain")
    _station_label(Vector2(275, -440), "04  Spring / gravity Area2D")
    _station_label(Vector2(680, -440), "05  CCD / ray / character")


func _make_stacks() -> void:
    for row in range(5):
        for col in range(4):
            _rigid_rect(
                Vector2(-880 + col * 49, 338 - row * 49),
                Vector2(44, 44),
                Color.from_hsv(0.52 + row * 0.06, 0.58, 0.95),
                1.5
            )
    var heavy := _rigid_circle(Vector2(-800, -220), 33, Color("#edaa5c"), 12.0)
    heavy.linear_velocity = Vector2(0, 40)


func _make_slopes() -> void:
    _static_rect("Ramp A", Vector2(-460, 240), Vector2(290, 24), Color("#78a59c"), -0.21)
    _static_rect("Ramp B", Vector2(-300, 115), Vector2(170, 20), Color("#92bbaa"), 0.28)
    for i in range(6):
        var ball := _rigid_circle(Vector2(-520 + i * 40, -260 - i * 32), 19, Color("#f7c984"), 1.0)
        var material := PhysicsMaterial.new()
        material.bounce = float(i) * 0.13
        material.friction = float(i) * 0.18
        ball.physics_material_override = material


func _pin(a: PhysicsBody2D, b: PhysicsBody2D, point: Vector2) -> void:
    var joint := PinJoint2D.new()
    joint.position = point
    add_child(joint)
    joint.node_a = joint.get_path_to(a)
    joint.node_b = joint.get_path_to(b)


func _make_chains() -> void:
    var fixed: PhysicsBody2D = _static_rect("Chain Support", Vector2(0, -270), Vector2(48, 22), Color("#dae1f3"))
    var parent: PhysicsBody2D = fixed
    for i in range(5):
        var link := _rigid_rect(Vector2(0, -213 + i * 59), Vector2(20, 50), Color("#9bc7e6"))
        _pin(parent, link, Vector2(0, -242 + i * 59))
        parent = link
    var pendulum_anchor := _static_rect("Pendulum Support", Vector2(110, -230), Vector2(34, 34), Color("#dae1f3"))
    var bob := _rigid_circle(Vector2(190, -30), 32, Color("#f2b478"), 6.0)
    _pin(pendulum_anchor, bob, pendulum_anchor.global_position)
    var groove_base := _static_rect("GrooveSupport", Vector2(-100, -230), Vector2(35, 35), Color("#d3e6f0"))
    var slider_mass := _rigid_rect(Vector2(-100, -95), Vector2(31, 31), Color("#f1bb9e"))
    var groove := GrooveJoint2D.new()
    groove.position = groove_base.position
    groove.length = 200
    groove.initial_offset = 110
    add_child(groove)
    groove.node_a = groove.get_path_to(groove_base)
    groove.node_b = groove.get_path_to(slider_mass)


func _make_springs_and_areas() -> void:
    var anchor := _static_rect("Spring Support", Vector2(322, -270), Vector2(44, 44), Color("#e0e6f3"))
    var mass := _rigid_circle(Vector2(495, -60), 35, Color("#c7a4ec"), 3.0)
    var spring := DampedSpringJoint2D.new()
    spring.position = Vector2(410, -170)
    add_child(spring)
    spring.node_a = spring.get_path_to(anchor)
    spring.node_b = spring.get_path_to(mass)
    spring.length = 230.0
    spring.rest_length = 155.0
    spring.stiffness = 35.0
    spring.damping = 0.8
    var anti_gravity := Area2D.new()
    anti_gravity.name = "UpwardGravityZone"
    anti_gravity.position = Vector2(400, 120)
    anti_gravity.collision_layer = 0
    anti_gravity.collision_mask = 1
    anti_gravity.monitoring = true
    anti_gravity.gravity_space_override = Area2D.SPACE_OVERRIDE_REPLACE
    anti_gravity.gravity_direction = Vector2.UP
    anti_gravity.gravity = 620.0
    _attach_rect(anti_gravity, Vector2(280, 190), Color(0.32, 0.75, 0.9, 0.19))
    add_child(anti_gravity)
    anti_gravity.body_entered.connect(_on_area_entered)
    for i in range(3):
        _rigid_circle(Vector2(340 + i * 58, -60), 20, Color("#9ee7dc"), 1.0)


func _launch_ccd() -> void:
    _projectile_count += 1
    var ball := _rigid_circle(Vector2(660, -40 - (_projectile_count % 3) * 24), 9, Color("#e4f9a9"), 1.0, true)
    ball.name = "FastCCD_%d" % _projectile_count
    ball.gravity_scale = 0.0
    ball.linear_velocity = Vector2(1800, 0)


func _make_ccd() -> void:
    _static_rect("Thin CCD Target", Vector2(920, -40), Vector2(8, 240), Color("#e88b7a"))
    _launch_ccd()
    _shape_cast = ShapeCast2D.new()
    _shape_cast.name = "ThinWallShapeCast"
    _shape_cast.position = Vector2(660, -280)
    var test_circle := CircleShape2D.new()
    test_circle.radius = 20
    _shape_cast.shape = test_circle
    _shape_cast.target_position = Vector2(300, 230)
    _shape_cast.enabled = true
    add_child(_shape_cast)


func _make_character() -> void:
    var character = WALKER.new()
    character.name = "AutonomousCharacterBody2D"
    character.position = Vector2(750, 245)
    _attach_rect(character, Vector2(38, 62), Color("#98f1be"))
    add_child(character)


func _make_camera() -> void:
    _camera = Camera2D.new()
    _camera.position = Vector2(0, 0)
    _camera.zoom = Vector2(0.63, 0.63)
    _camera.enabled = true
    add_child(_camera)


func _make_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(14, 14)
    layer.add_child(panel)
    var margin := MarginContainer.new()
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 11)
    panel.add_child(margin)
    var col := VBoxContainer.new()
    margin.add_child(col)
    var title := Label.new()
    title.text = "CGAME | 2D PHYSICS LAB"
    title.add_theme_font_size_override("font_size", 21)
    col.add_child(title)
    var controls := Label.new()
    controls.text = "WASD: камера | колесо: масштаб | B: шар | C: CCD\nSpace: импульс | X: +100 тел | R: сброс | F1: 3D"
    col.add_child(controls)
    _stats = Label.new()
    col.add_child(_stats)
    _event_label = Label.new()
    _event_label.text = "Зона Area2D: ожидаем столкновений"
    col.add_child(_event_label)
    var row := HBoxContainer.new()
    col.add_child(row)
    var three_d := Button.new()
    three_d.text = "Перейти в 3D [F1]"
    three_d.pressed.connect(func() -> void: get_tree().change_scene_to_file(LAB_3D))
    row.add_child(three_d)
    var reset := Button.new()
    reset.text = "Сброс [R]"
    reset.pressed.connect(func() -> void: get_tree().reload_current_scene())
    row.add_child(reset)
    var stress := Button.new()
    stress.text = "Стресс +100 [X]"
    stress.pressed.connect(_spawn_stress)
    row.add_child(stress)


func _on_area_entered(body: Node2D) -> void:
    if body is RigidBody2D:
        _hits += 1
        if _event_label != null:
            _event_label.text = "Area2D: %s | событий: %d" % [body.name, _hits]


func _spawn_stress() -> void:
    for i in range(100):
        var x := 670.0 + float(i % 10) * 27.0
        var y := -370.0 + float(i / 10) * 26.0
        _rigid_rect(Vector2(x, y), Vector2(23, 23), Color("#b3a4e6"), 0.6)


func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _camera.zoom = (_camera.zoom * 1.12).clamp(Vector2.ONE * 0.3, Vector2.ONE * 2.0)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _camera.zoom = (_camera.zoom / 1.12).clamp(Vector2.ONE * 0.3, Vector2.ONE * 2.0)
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_F1:
                get_tree().change_scene_to_file(LAB_3D)
            KEY_R:
                get_tree().reload_current_scene()
            KEY_B:
                _rigid_circle(_camera.position + Vector2(0, -180), 25, Color("#ecdd94"), 2.0)
            KEY_C:
                _launch_ccd()
            KEY_X:
                _spawn_stress()
            KEY_SPACE:
                for body in get_tree().get_nodes_in_group("demo_dynamic_2d"):
                    if body is RigidBody2D:
                        body.apply_central_impulse(Vector2(0, -body.mass * 280))


func _physics_process(delta: float) -> void:
    _timer += delta
    if _timer >= 0.4:
        _timer = 0.0
        var query := PhysicsRayQueryParameters2D.create(Vector2(650, -350), Vector2(950, 300))
        var result := get_world_2d().direct_space_state.intersect_ray(query)
        var collider: String = str(result["collider"].name) if not result.is_empty() else "нет"
        _stats.text = "FPS: %d | Bodies: %d | Ray2D: %s | ShapeCast: %s" % [
            Engine.get_frames_per_second(), get_tree().get_nodes_in_group("demo_dynamic_2d").size(),
            collider, str(_shape_cast.is_colliding())
        ]


func _process(delta: float) -> void:
    var direction := Vector2.ZERO
    if Input.is_key_pressed(KEY_A):
        direction.x -= 1
    if Input.is_key_pressed(KEY_D):
        direction.x += 1
    if Input.is_key_pressed(KEY_W):
        direction.y -= 1
    if Input.is_key_pressed(KEY_S):
        direction.y += 1
    if direction.length_squared() > 0:
        _camera.position += direction.normalized() * 850.0 * delta / _camera.zoom.x
