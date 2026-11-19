extends Node2D
## Advanced interactive 2D experiments: vortex, conveyor velocity, a
## local gravity volume and impact-triggered scripted fragmentation.

const BREAKABLE = preload("res://breakable_2d.gd")
const VORTEX_CENTER := Vector2(1020.0, -260.0)
const VORTEX_RADIUS := 145.0

var _vortex_enabled := true
var _vortex_strength := 780.0
var _belt_enabled := true
var _belt_speed := 260.0
var _gravity_enabled := true
var _gravity_zone: Area2D
var _belt: StaticBody2D
var _label: Label
var _round := 0
var _time := 0.0


func setup() -> void:
    _create_vortex()
    _create_conveyor()
    _create_gravity_zone()
    _create_breakable()
    _create_hud()
    _refresh()


func _vertices(size: Vector2) -> PackedVector2Array:
    var half := size / 2.0
    return PackedVector2Array([
        Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
        Vector2(half.x, half.y), Vector2(-half.x, half.y)
    ])


func _static_box(name: String, at: Vector2, size: Vector2, color: Color) -> StaticBody2D:
    var body := StaticBody2D.new()
    body.name = name
    body.position = at
    var collider := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    var visual := Polygon2D.new()
    visual.polygon = _vertices(size)
    visual.color = color
    body.add_child(visual)
    add_child(body)
    return body


func _spawn_dynamic(at: Vector2, color: Color, mass := 1.0) -> RigidBody2D:
    var body := RigidBody2D.new()
    body.name = "AdvancedDynamicBody2D"
    body.position = at
    body.mass = mass
    var collider := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = Vector2.ONE * 27.0
    collider.shape = shape
    body.add_child(collider)
    var visual := Polygon2D.new()
    visual.polygon = _vertices(shape.size)
    visual.color = color
    body.add_child(visual)
    get_parent().add_child(body)
    body.add_to_group("demo_dynamic_2d")
    return body


func _station_label(name: String, at: Vector2, words: String) -> void:
    var label := Label.new()
    label.name = name
    label.position = at
    label.text = words
    label.add_theme_font_size_override("font_size", 20)
    add_child(label)


func _create_vortex() -> void:
    var ring := Polygon2D.new()
    ring.name = "VortexField2D"
    ring.position = VORTEX_CENTER
    var polygon := PackedVector2Array()
    for index in range(40):
        var angle := TAU * float(index) / 40.0
        polygon.append(Vector2.RIGHT.rotated(angle) * VORTEX_RADIUS)
    ring.polygon = polygon
    ring.color = Color(0.24, 0.8, 0.98, 0.18)
    add_child(ring)
    _station_label("VortexLabel", Vector2(870, -485), "VORTEX [H]")
    for index in range(6):
        var angle := TAU * float(index) / 6.0
        _spawn_dynamic(VORTEX_CENTER + Vector2.RIGHT.rotated(angle) * 95, Color("#b4eaf4"), 1.0)


func _create_conveyor() -> void:
    _belt = _static_box("ConveyorBelt2D", Vector2(-30, 326), Vector2(315, 20), Color("#bba077"))
    var contact := PhysicsMaterial.new()
    contact.friction = 1.5
    contact.rough = true
    _belt.physics_material_override = contact
    _station_label("BeltLabel", Vector2(-190, 280), "CONVEYOR [I]")
    for index in range(5):
        var box := _spawn_dynamic(Vector2(-155 + index * 60, 250 - index * 4), Color("#eed4a7"), 3.0)
        var physical := PhysicsMaterial.new()
        physical.friction = 1.4
        box.physics_material_override = physical


func _create_gravity_zone() -> void:
    _gravity_zone = Area2D.new()
    _gravity_zone.name = "LocalGravityWell2D"
    _gravity_zone.position = Vector2(-330, 100)
    _gravity_zone.collision_layer = 0
    _gravity_zone.collision_mask = 1
    _gravity_zone.gravity_space_override = Area2D.SPACE_OVERRIDE_REPLACE
    _gravity_zone.gravity_direction = Vector2.UP
    _gravity_zone.gravity = 700.0
    _gravity_zone.priority = 6.0
    var collider := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = Vector2(230, 260)
    collider.shape = shape
    _gravity_zone.add_child(collider)
    add_child(_gravity_zone)
    var visual := Polygon2D.new()
    visual.name = "GravityVisual2D"
    visual.position = _gravity_zone.position
    visual.polygon = _vertices(shape.size)
    visual.color = Color(0.56, 0.45, 0.99, 0.14)
    add_child(visual)
    _station_label("GravityLabel", Vector2(-455, -65), "LOCAL GRAVITY [G]")
    for index in range(3):
        _spawn_dynamic(Vector2(-405 + index * 70, 60), Color("#d3bef2"))


func _create_breakable() -> void:
    _station_label("BreakableLabel", Vector2(900, 80), "SHATTER [L]")
    spawn_fracture_test()


func spawn_fracture_test() -> void:
    _round += 1
    var target = BREAKABLE.new()
    target.name = "BreakableTarget2D"
    target.position = Vector2(965, 185 - float((_round - 1) % 3) * 50)
    target.mass = 5.0
    var collider := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = Vector2.ONE * 48
    collider.shape = shape
    target.add_child(collider)
    var visual := Polygon2D.new()
    visual.polygon = _vertices(shape.size)
    visual.color = Color("#f0ab78")
    target.add_child(visual)
    get_parent().add_child(target)
    target.add_to_group("demo_dynamic_2d")
    var projectile := _spawn_dynamic(Vector2(1080, target.position.y), Color("#b4f2e3"), 10.0)
    projectile.name = "FractureProjectile2D"
    projectile.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
    projectile.linear_velocity = Vector2(-960, 0)


func _create_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "AdvancedHUD2D"
    add_child(layer)
    var panel := PanelContainer.new()
    panel.anchor_left = 1.0
    panel.anchor_right = 1.0
    panel.anchor_top = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = -360.0
    panel.offset_right = -12.0
    panel.offset_top = -235.0
    panel.offset_bottom = -12.0
    layer.add_child(panel)
    var padding := MarginContainer.new()
    panel.add_child(padding)
    for edge in ["left", "right", "top", "bottom"]:
        padding.add_theme_constant_override("margin_" + edge, 9)
    var col := VBoxContainer.new()
    padding.add_child(col)
    var title := Label.new()
    title.text = "ADVANCED PHYSICS | 2D"
    col.add_child(title)
    _label = Label.new()
    col.add_child(_label)
    var row := HBoxContainer.new()
    col.add_child(row)
    _button(row, "Вихрь [H]", _toggle_vortex)
    _button(row, "Лента [I]", _toggle_belt)
    _button(row, "g [G]", _toggle_gravity)
    var row2 := HBoxContainer.new()
    col.add_child(row2)
    _button(row2, "Удар [L]", spawn_fracture_test)
    _button(row2, "Реверс [;]", _reverse_belt)
    _slider(col, "Сила вихря", 0, 1800, _vortex_strength, func(v: float) -> void:
        _vortex_strength = v
        _refresh()
    )
    _slider(col, "Скорость ленты", 0, 850, _belt_speed, func(v: float) -> void:
        _belt_speed = v
        _refresh()
    )


func _button(row: HBoxContainer, caption: String, action: Callable) -> void:
    var button := Button.new()
    button.text = caption
    row.add_child(button)
    button.pressed.connect(action)


func _slider(col: VBoxContainer, caption: String, lower: float, upper: float, initial: float, callback: Callable) -> void:
    var title := Label.new()
    title.text = caption
    col.add_child(title)
    var slider := HSlider.new()
    slider.min_value = lower
    slider.max_value = upper
    slider.step = 5.0
    slider.value = initial
    col.add_child(slider)
    slider.value_changed.connect(callback)


func _toggle_vortex() -> void:
    _vortex_enabled = not _vortex_enabled
    _refresh()


func _toggle_belt() -> void:
    _belt_enabled = not _belt_enabled
    _refresh()


func _reverse_belt() -> void:
    _belt_speed = -_belt_speed
    _refresh()


func _toggle_gravity() -> void:
    _gravity_enabled = not _gravity_enabled
    _gravity_zone.gravity_space_override = Area2D.SPACE_OVERRIDE_REPLACE if _gravity_enabled else Area2D.SPACE_OVERRIDE_DISABLED
    _refresh()


func _refresh() -> void:
    if _belt != null:
        _belt.constant_linear_velocity = Vector2(_belt_speed if _belt_enabled else 0.0, 0.0)
    if _label != null:
        _label.text = "Вихрь: %s %.0f | лента: %s %.0f\nЛокальная g: %s | ударов: %d" % [
            "ON" if _vortex_enabled else "OFF", _vortex_strength,
            "ON" if _belt_enabled else "OFF", _belt_speed,
            "ON" if _gravity_enabled else "OFF", _round
        ]


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_H:
                _toggle_vortex()
            KEY_I:
                _toggle_belt()
            KEY_G:
                _toggle_gravity()
            KEY_L:
                spawn_fracture_test()
            KEY_SEMICOLON:
                _reverse_belt()


func _physics_process(delta: float) -> void:
    if not _vortex_enabled:
        return
    _time += delta
    for node in get_tree().get_nodes_in_group("demo_dynamic_2d"):
        if not node is RigidBody2D:
            continue
        var body := node as RigidBody2D
        if body.freeze:
            continue
        var offset := body.global_position - VORTEX_CENTER
        var distance := offset.length()
        if distance < 12.0 or distance >= VORTEX_RADIUS:
            continue
        var tangent := Vector2(-offset.y, offset.x).normalized()
        var radial := -offset.normalized()
        var weight := 1.0 - distance / VORTEX_RADIUS
        var lift := Vector2.UP * (0.24 + 0.08 * sin(_time))
        var acceleration := (tangent + radial * 0.42 + lift) * _vortex_strength * weight
        body.apply_central_force(acceleration * body.mass)
