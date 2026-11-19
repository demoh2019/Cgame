extends Node3D
## Additional 3D test stations: a bounded vortex, a contact-velocity
## conveyor, local Area3D gravity and procedural impact fragmentation.

const BREAKABLE = preload("res://breakable_3d.gd")
const VORTEX_CENTER := Vector3(-28.0, 3.0, 24.0)
const VORTEX_RADIUS := 5.0
const BREAKABLE_POSITION := Vector3(14.0, 4.2, 24.0)

var _vortex_enabled := true
var _vortex_strength := 28.0
var _belt_enabled := true
var _belt_speed := 6.0
var _gravity_enabled := true
var _gravity_area: Area3D
var _vortex_area: Area3D
var _conveyor: StaticBody3D
var _readout: Label
var _elapsed := 0.0
var _round := 0


func setup() -> void:
    _make_vortex()
    _make_conveyor()
    _make_local_gravity()
    _make_fracture_range()
    _make_hud()
    _update_controls()


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.78
    if color.a < 0.99:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material


func _static_box(name: String, at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = name
    body.position = at
    var collider := CollisionShape3D.new()
    var collision := BoxShape3D.new()
    collision.size = size
    collider.shape = collision
    body.add_child(collider)
    var mesh_node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_node.mesh = mesh
    mesh_node.material_override = _material(color)
    body.add_child(mesh_node)
    add_child(body)
    return body


func _demo_box(at: Vector3, color: Color, mass := 1.0) -> RigidBody3D:
    var box := RigidBody3D.new()
    box.name = "AdvancedDynamicBox"
    box.position = at
    box.mass = mass
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3.ONE * 1.0
    collider.shape = shape
    box.add_child(collider)
    var visual := MeshInstance3D.new()
    var cube := BoxMesh.new()
    cube.size = shape.size
    visual.mesh = cube
    visual.material_override = _material(color)
    box.add_child(visual)
    get_parent().add_child(box)
    box.add_to_group("demo_dynamic")
    return box


func _label(name: String, at: Vector3, label_text: String) -> void:
    var sign := Label3D.new()
    sign.name = name
    sign.text = label_text
    sign.position = at
    sign.font_size = 29
    sign.pixel_size = 0.012
    sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(sign)


func _make_vortex() -> void:
    _vortex_area = Area3D.new()
    _vortex_area.name = "VortexDetector"
    _vortex_area.position = VORTEX_CENTER
    _vortex_area.collision_layer = 0
    _vortex_area.collision_mask = 1
    _vortex_area.monitoring = true
    var detector_shape := CollisionShape3D.new()
    var sphere := SphereShape3D.new()
    sphere.radius = VORTEX_RADIUS
    detector_shape.shape = sphere
    _vortex_area.add_child(detector_shape)
    add_child(_vortex_area)
    var disk := MeshInstance3D.new()
    disk.name = "VortexZone"
    disk.position = Vector3(VORTEX_CENTER.x, 0.16, VORTEX_CENTER.z)
    var mesh := CylinderMesh.new()
    mesh.top_radius = VORTEX_RADIUS
    mesh.bottom_radius = VORTEX_RADIUS
    mesh.height = 0.03
    disk.mesh = mesh
    disk.material_override = _material(Color(0.25, 0.8, 0.9, 0.25))
    add_child(disk)
    _label("VortexLabel", Vector3(-28, 7.0, 24), "VORTEX [H]")
    for index in range(5):
        var angle := float(index) * TAU / 5.0
        _demo_box(
            Vector3(-28 + cos(angle) * 3.2, 1.8 + float(index) * 0.55, 24 + sin(angle) * 3.2),
            Color("#b2eff4"), 1.0
        )


func _make_conveyor() -> void:
    _conveyor = _static_box("ConveyorBelt3D", Vector3(-14, 1.15, 24), Vector3(10, 0.45, 6.5), Color("#c6a16a"))
    var phys := PhysicsMaterial.new()
    phys.friction = 1.4
    phys.rough = true
    _conveyor.physics_material_override = phys
    _label("ConveyorLabel", Vector3(-14, 5.8, 24), "CONVEYOR [I]")
    for index in range(5):
        var body := _demo_box(Vector3(-17.5 + index * 1.8, 3.5, 24), Color("#f9d49d"), 2.2)
        var mat := PhysicsMaterial.new()
        mat.friction = 1.35
        body.physics_material_override = mat


func _make_local_gravity() -> void:
    _gravity_area = Area3D.new()
    _gravity_area.name = "LocalGravityWell"
    _gravity_area.position = Vector3(0, 3.0, 24)
    _gravity_area.collision_layer = 0
    _gravity_area.collision_mask = 1
    _gravity_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
    _gravity_area.gravity_direction = Vector3.UP
    _gravity_area.gravity = 14.0
    _gravity_area.priority = 5.0
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(10, 6.0, 10)
    collider.shape = shape
    _gravity_area.add_child(collider)
    add_child(_gravity_area)
    var node := MeshInstance3D.new()
    node.name = "GravityFieldVisual"
    node.position = _gravity_area.position
    var mesh := BoxMesh.new()
    mesh.size = shape.size
    node.mesh = mesh
    node.material_override = _material(Color(0.58, 0.36, 0.95, 0.09))
    add_child(node)
    _label("GravityLabel", Vector3(0, 7, 24), "LOCAL GRAVITY [G]")
    for index in range(4):
        _demo_box(Vector3(-3 + index * 2, 1.6 + index * 0.6, 24), Color("#cebcfa"), 1.4)


func _make_fracture_range() -> void:
    _static_box("FractureAnvil", Vector3(14, 0.65, 24), Vector3(8.5, 1.3, 8.5), Color("#9d877a"))
    _label("FractureLabel", Vector3(14, 7, 24), "BREAKABLE [L]")
    spawn_fracture_test()


func spawn_fracture_test() -> void:
    # Existing debris persists until the user reloads the scene.
    _round += 1
    var target = BREAKABLE.new()
    target.name = "BreakableTarget3D"
    target.position = BREAKABLE_POSITION + Vector3(0, float((_round - 1) % 3) * 2.0, 0)
    target.mass = 4.0
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3.ONE * 1.6
    collider.shape = shape
    target.add_child(collider)
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = shape.size
    visual.mesh = mesh
    visual.material_override = _material(Color("#f1a77b"))
    target.add_child(visual)
    get_parent().add_child(target)
    target.add_to_group("demo_dynamic")
    var projectile := _demo_box(Vector3(14, target.position.y, 28.5), Color("#bde7f1"), 8.0)
    projectile.name = "FractureProjectile"
    projectile.continuous_cd = true
    projectile.linear_velocity = Vector3(0, 0, -23.0)


func _make_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "AdvancedHUD3D"
    add_child(layer)
    var panel := PanelContainer.new()
    panel.anchor_left = 1.0
    panel.anchor_right = 1.0
    panel.anchor_top = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = -354.0
    panel.offset_right = -12.0
    panel.offset_top = -246.0
    panel.offset_bottom = -12.0
    layer.add_child(panel)
    var margin := MarginContainer.new()
    panel.add_child(margin)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 9)
    var col := VBoxContainer.new()
    margin.add_child(col)
    var title := Label.new()
    title.text = "ADVANCED PHYSICS | 3D"
    col.add_child(title)
    _readout = Label.new()
    col.add_child(_readout)
    var controls := HBoxContainer.new()
    col.add_child(controls)
    _add_button(controls, "Вихрь [H]", _toggle_vortex)
    _add_button(controls, "Лента [I]", _toggle_conveyor)
    _add_button(controls, "g [G]", _toggle_gravity)
    var controls2 := HBoxContainer.new()
    col.add_child(controls2)
    _add_button(controls2, "Разбить [L]", spawn_fracture_test)
    _add_button(controls2, "Реверс [;]", _reverse_belt)
    _add_slider(col, "Сила вихря", 0, 65, _vortex_strength, func(value: float) -> void:
        _vortex_strength = value
        _update_controls()
    )
    _add_slider(col, "Скорость ленты", 0, 16, _belt_speed, func(value: float) -> void:
        _belt_speed = value
        _update_controls()
    )


func _add_button(row: HBoxContainer, text_value: String, action: Callable) -> void:
    var button := Button.new()
    button.text = text_value
    row.add_child(button)
    button.pressed.connect(action)


func _add_slider(col: VBoxContainer, caption: String, minimum: float, maximum: float, value: float, action: Callable) -> void:
    var slider_label := Label.new()
    slider_label.text = caption
    col.add_child(slider_label)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.value = value
    slider.step = 0.5
    col.add_child(slider)
    slider.value_changed.connect(action)


func _toggle_vortex() -> void:
    _vortex_enabled = not _vortex_enabled
    _update_controls()


func _toggle_conveyor() -> void:
    _belt_enabled = not _belt_enabled
    _update_controls()


func _reverse_belt() -> void:
    _belt_speed = -_belt_speed
    _update_controls()


func _toggle_gravity() -> void:
    _gravity_enabled = not _gravity_enabled
    _gravity_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE if _gravity_enabled else Area3D.SPACE_OVERRIDE_DISABLED
    _update_controls()


func _update_controls() -> void:
    if _conveyor != null:
        _conveyor.constant_linear_velocity = Vector3(_belt_speed if _belt_enabled else 0.0, 0, 0)
    if _readout != null:
        _readout.text = "Вихрь %s (%.0f) | лента %s (%.1f)\nЛокальная g: %s | разрушений: %d" % [
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
                _toggle_conveyor()
            KEY_G:
                _toggle_gravity()
            KEY_L:
                spawn_fracture_test()
            KEY_SEMICOLON:
                _reverse_belt()


func _physics_process(delta: float) -> void:
    if not _vortex_enabled:
        return
    _elapsed += delta
    for node in _vortex_area.get_overlapping_bodies():
        if not node is RigidBody3D:
            continue
        var body := node as RigidBody3D
        if body.freeze:
            continue
        var from_center := body.global_position - VORTEX_CENTER
        var horizontal := Vector2(from_center.x, from_center.z)
        var distance := horizontal.length()
        if distance < 0.3 or distance >= VORTEX_RADIUS:
            continue
        if absf(from_center.y) >= 5.0:
            continue
        var strength := _vortex_strength * (1.0 - distance / VORTEX_RADIUS)
        var tangential := Vector3(-horizontal.y, 0, horizontal.x).normalized()
        var inward := Vector3(-horizontal.x, 0, -horizontal.y).normalized()
        var lift := Vector3.UP * (0.5 + 0.1 * sin(_elapsed))
        var force := (tangential * 1.2 + inward * 0.5 + lift) * strength * body.mass
        body.apply_central_force(force)
