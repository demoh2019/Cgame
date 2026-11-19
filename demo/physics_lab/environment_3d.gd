extends Node3D
## Interactive forces for the 3D lab. Water, wind and magnetic attraction are
## intentionally scripted approximations, not built-in fluid/air/FEM solvers.

const WATER_XZ := Vector2(28.0, -11.0)
const WATER_SIZE := Vector2(11.5, 14.4)
const MAGNET_POSITION := Vector3(28.0, 2.2, 11.0)
const DRAG_STIFFNESS := 95.0
const DRAG_DAMPING := 19.0

var _camera: Camera3D
var _water: Area3D
var _water_shape: BoxShape3D
var _water_mesh: BoxMesh
var _wind_label: Label3D
var _status: Label
var _water_height := 2.6
var _fluid_density := 1.5
var _water_current := 1.6
var _wave_phase := 0.0
var _waves := true
var _wind_on := false
var _wind_strength := 15.0
var _wind_angle := 0.0
var _magnet_on := false
var _magnet_repels := false
var _gravity_scale := 1.0
var _spawn_mass := 2.0
var _selected_friction := 0.65
var _selected_bounce := 0.15
var _held: RigidBody3D
var _held_distance := 8.0
var _dragging := false
var _request_pick := false
var _request_blast := false
var _request_push := false
var _event_counter := 0


func setup(camera: Camera3D) -> void:
    _camera = camera
    _create_water()
    _create_magnet()
    _create_hud()
    spawn_water_object(false)
    spawn_water_object(true)
    _update_status()


func _make_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.5
    if color.a < 0.999:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _create_water() -> void:
    _water = Area3D.new()
    _water.name = "WaterVolume3D"
    _water.collision_layer = 0
    _water.collision_mask = 1
    _water.monitoring = true
    add_child(_water)
    var collider := CollisionShape3D.new()
    _water_shape = BoxShape3D.new()
    collider.shape = _water_shape
    _water.add_child(collider)
    var visual := MeshInstance3D.new()
    _water_mesh = BoxMesh.new()
    visual.mesh = _water_mesh
    visual.material_override = _make_material(Color(0.12, 0.54, 0.93, 0.23))
    _water.add_child(visual)
    _set_water_height(_water_height)
    # Visible boundaries give the basin physical walls, but the water itself
    # does not create solid contacts.
    _make_static_box("PoolWallWest", Vector3(21.95, 1.65, -11), Vector3(0.5, 3.3, 15.0), Color("#729fb7"))
    _make_static_box("PoolWallEast", Vector3(34.05, 1.65, -11), Vector3(0.5, 3.3, 15.0), Color("#729fb7"))
    _make_static_box("PoolWallNorth", Vector3(28, 1.65, -18.45), Vector3(11.5, 3.3, 0.5), Color("#729fb7"))
    _make_static_box("PoolWallSouth", Vector3(28, 1.65, -3.55), Vector3(11.5, 3.3, 0.5), Color("#729fb7"))
    var caption := Label3D.new()
    caption.name = "WaterCaption"
    caption.text = "WATER | buoyancy + drag + flow"
    caption.position = Vector3(28, 4.2, -11)
    caption.font_size = 32
    caption.pixel_size = 0.011
    caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(caption)


func _make_static_box(name: String, position_3d: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = name
    body.position = position_3d
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.material_override = _make_material(color)
    body.add_child(mesh)
    add_child(body)


func _set_water_height(level: float) -> void:
    _water_height = clampf(level, 0.5, 4.0)
    _water.position = Vector3(WATER_XZ.x, _water_height * 0.5, WATER_XZ.y)
    var dimensions := Vector3(WATER_SIZE.x, _water_height, WATER_SIZE.y)
    _water_shape.size = dimensions
    _water_mesh.size = dimensions
    _update_status()


func _create_magnet() -> void:
    _make_static_box("MagnetCore", MAGNET_POSITION, Vector3(1.1, 1.5, 1.1), Color("#ef849f"))
    var label := Label3D.new()
    label.name = "MagnetCaption"
    label.text = "MAGNET (M / N)"
    label.position = MAGNET_POSITION + Vector3(0, 2.1, 0)
    label.font_size = 34
    label.pixel_size = 0.011
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(label)
    _wind_label = Label3D.new()
    _wind_label.name = "WindCaption"
    _wind_label.position = Vector3(28, 6.0, 11)
    _wind_label.font_size = 35
    _wind_label.pixel_size = 0.011
    _wind_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(_wind_label)
    for index in range(6):
        var b := _spawn_box(Vector3(24.0 + float(index % 3) * 3.2, 5.3 + float(index / 3) * 1.9, 7.0 + float(index % 2) * 6.0), 1.0)
        b.add_to_group("lab_metal")


func _spawn_box(world_position: Vector3, mass: float, magnetic := false, radius := 0.66) -> RigidBody3D:
    var body := RigidBody3D.new()
    body.name = "InteractiveMetal" if magnetic else "InteractiveObject"
    body.position = world_position
    body.mass = maxf(0.1, mass)
    var contact := PhysicsMaterial.new()
    contact.friction = _selected_friction
    contact.bounce = _selected_bounce
    body.physics_material_override = contact
    body.continuous_cd = true
    var collider := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3.ONE * radius * 2.0
    collider.shape = box
    body.add_child(collider)
    var mesh_node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = box.size
    mesh_node.mesh = mesh
    mesh_node.material_override = _make_material(Color("#f1a9b4") if magnetic else Color("#a5efd4"))
    body.add_child(mesh_node)
    get_parent().add_child(body)
    body.add_to_group("demo_dynamic")
    if magnetic:
        body.add_to_group("lab_metal")
    body.gravity_scale = _gravity_scale
    body.set_meta("lab_volume", pow(radius * 2.0, 3))
    body.set_meta("lab_half_height", radius)
    return body


func spawn_water_object(heavy: bool) -> void:
    var mass := 9.0 if heavy else _spawn_mass
    var body := _spawn_box(Vector3(25.5 if heavy else 30.3, 5.5, -11.0), mass)
    body.name = "Sinker" if heavy else "Floater"
    _event_counter += 1
    _update_status()


func _create_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "InteractionHUD3D"
    add_child(layer)
    var panel := PanelContainer.new()
    panel.anchor_left = 1.0
    panel.anchor_right = 1.0
    panel.offset_left = -375.0
    panel.offset_right = -12.0
    panel.offset_top = 12.0
    layer.add_child(panel)
    var margin := MarginContainer.new()
    panel.add_child(margin)
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 9)
    var column := VBoxContainer.new()
    margin.add_child(column)
    var title := Label.new()
    title.text = "INTERACTIONS | 3D"
    title.add_theme_font_size_override("font_size", 19)
    column.add_child(title)
    var help := Label.new()
    help.text = "ЛКМ: взять / отпустить | F: толкнуть | P: взрыв\nV: ветер | T: поворот | M: магнит | N: полюс\nO: объект в воду | J/U: уровень | Y: волны\nK: гравитация | Z: заморозить выбранное"
    column.add_child(help)
    _status = Label.new()
    column.add_child(_status)
    _add_slider(column, "Сила ветра", 0.0, 70.0, _wind_strength, func(v: float) -> void:
        _wind_strength = v
        _update_status()
    )
    _add_slider(column, "Уровень воды", 0.5, 4.0, _water_height, func(v: float) -> void:
        _set_water_height(v)
    )
    _add_slider(column, "Плотность воды", 0.1, 5.0, _fluid_density, func(v: float) -> void:
        _fluid_density = v
        _update_status()
    )
    _add_slider(column, "Течение воды", -6.0, 6.0, _water_current, func(v: float) -> void:
        _water_current = v
        _update_status()
    )
    _add_slider(column, "Трение выбранного тела", 0.0, 2.0, _selected_friction, func(v: float) -> void:
        _selected_friction = v
        _apply_selected_material()
    )
    _add_slider(column, "Упругость выбранного тела", 0.0, 1.0, _selected_bounce, func(v: float) -> void:
        _selected_bounce = v
        _apply_selected_material()
    )
    _add_slider(column, "Масса нового куба", 0.5, 20.0, _spawn_mass, func(v: float) -> void:
        _spawn_mass = v
        _update_status()
    )
    var row1 := HBoxContainer.new()
    column.add_child(row1)
    _add_button(row1, "Дерево / лёгкий", func() -> void: spawn_water_object(false))
    _add_button(row1, "Камень / тяжёлый", func() -> void: spawn_water_object(true))
    var row2 := HBoxContainer.new()
    column.add_child(row2)
    _add_button(row2, "Ветер [V]", _toggle_wind)
    _add_button(row2, "Магнит [M]", _toggle_magnet)
    _add_button(row2, "Взрыв [P]", func() -> void: _request_blast = true)
    var row3 := HBoxContainer.new()
    column.add_child(row3)
    _add_button(row3, "Волны [Y]", _toggle_waves)
    _add_button(row3, "Повернуть ветер [T]", _rotate_wind)
    _add_button(row3, "Гравитация [K]", _cycle_gravity)


func _add_slider(column: VBoxContainer, name: String, lower: float, upper: float, current: float, callback: Callable) -> void:
    var label := Label.new()
    label.text = name
    column.add_child(label)
    var slider := HSlider.new()
    slider.min_value = lower
    slider.max_value = upper
    slider.step = 0.1
    slider.value = current
    column.add_child(slider)
    slider.value_changed.connect(callback)


func _add_button(row: HBoxContainer, name: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = name
    row.add_child(button)
    button.pressed.connect(callback)


func _toggle_wind() -> void:
    _wind_on = not _wind_on
    _update_status()


func _toggle_magnet() -> void:
    _magnet_on = not _magnet_on
    _update_status()


func _toggle_waves() -> void:
    _waves = not _waves
    _update_status()


func _rotate_wind() -> void:
    _wind_angle += PI / 4.0
    _update_status()


func _cycle_gravity() -> void:
    # Do not overwrite global project physics settings: only demo bodies.
    if is_equal_approx(_gravity_scale, 1.0):
        _gravity_scale = 0.0
    elif is_zero_approx(_gravity_scale):
        _gravity_scale = -0.6
    else:
        _gravity_scale = 1.0
    for node in get_tree().get_nodes_in_group("demo_dynamic"):
        if node is RigidBody3D:
            node.gravity_scale = _gravity_scale
    _update_status()


func _apply_selected_material() -> void:
    if not is_instance_valid(_held):
        return
    var material := PhysicsMaterial.new()
    material.friction = _selected_friction
    material.bounce = _selected_bounce
    _held.physics_material_override = material


func _toggle_freeze() -> void:
    if is_instance_valid(_held):
        _held.freeze = not _held.freeze
        _update_status()


func _update_status() -> void:
    if _status == null:
        return
    _status.text = "Вода: %.1fm | плотность: %.1f | течение: %.1f | ветер: %s %.0f\nМагнит: %s (%s) | g: %.1f | волны: %s" % [
        _water_height, _fluid_density, _water_current, "ON" if _wind_on else "OFF", _wind_strength,
        "ON" if _magnet_on else "OFF", "отталкивание" if _magnet_repels else "притяжение",
        _gravity_scale, "ON" if _waves else "OFF"
    ]
    if is_instance_valid(_held):
        _status.text += "\nВыбрано: %s | масса %.1f кг | %s" % [
            _held.name, _held.mass, "заморожено" if _held.freeze else "активно"
        ]
    if _wind_label != null:
        _wind_label.text = "WIND %.0f | %s" % [_wind_strength, "ON" if _wind_on else "OFF"]


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _request_pick = true
            _dragging = true
        else:
            _dragging = false
            _request_pick = false
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_F:
                _request_push = true
            KEY_P:
                _request_blast = true
            KEY_V:
                _toggle_wind()
            KEY_T:
                _rotate_wind()
            KEY_M:
                _toggle_magnet()
            KEY_N:
                _magnet_repels = not _magnet_repels
                _update_status()
            KEY_Y:
                _toggle_waves()
            KEY_O:
                spawn_water_object(false)
            KEY_J:
                _set_water_height(_water_height - 0.3)
            KEY_U:
                _set_water_height(_water_height + 0.3)
            KEY_K:
                _cycle_gravity()
            KEY_Z:
                _toggle_freeze()


func _ray_query() -> Dictionary:
    var viewport := _camera.get_viewport()
    var coords := viewport.get_mouse_position()
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        coords = viewport.get_visible_rect().size * 0.5
    var origin := _camera.project_ray_origin(coords)
    var direction := _camera.project_ray_normal(coords)
    var params := PhysicsRayQueryParameters3D.create(origin, origin + direction * 150.0)
    params.collide_with_areas = false
    return get_world_3d().direct_space_state.intersect_ray(params)


func _pick() -> void:
    _request_pick = false
    var hit := _ray_query()
    if hit.is_empty():
        _held = null
        return
    var candidate := hit["collider"] as RigidBody3D
    if candidate == null or candidate is VehicleBody3D:
        _held = null
        return
    _held = candidate
    _held_distance = clampf(_camera.global_position.distance_to(hit["position"]), 2.0, 40.0)
    _held.sleeping = false
    _update_status()


func _push_target() -> void:
    # Impulses must be one-off, never once per physics tick.
    var hit := _ray_query()
    if hit.is_empty():
        return
    var body := hit["collider"] as RigidBody3D
    if body != null and not body.freeze:
        body.apply_central_impulse(_camera.global_transform.basis.z * -body.mass * 8.0)


func _explode() -> void:
    _request_blast = false
    var hit := _ray_query()
    var center: Vector3 = hit["position"] if not hit.is_empty() else _camera.global_position - _camera.global_transform.basis.z * 12.0
    for node in get_tree().get_nodes_in_group("demo_dynamic"):
        if node is RigidBody3D and not node.freeze:
            var offset: Vector3 = node.global_position - center
            var dist := offset.length()
            if dist > 0.001 and dist < 10.0:
                var falloff := pow(1.0 - dist / 10.0, 2)
                node.apply_central_impulse(offset / dist * node.mass * 35.0 * falloff)


func _fluid_properties(body: RigidBody3D) -> Vector2:
    if body.has_meta("lab_volume"):
        return Vector2(float(body.get_meta("lab_volume")), float(body.get_meta("lab_half_height")))
    var volume := 1.0
    var half_height := 0.5
    for child in body.get_children():
        if child is CollisionShape3D:
            var box_shape := child.shape as BoxShape3D
            var sphere_shape := child.shape as SphereShape3D
            if box_shape != null:
                var dimensions: Vector3 = box_shape.size
                volume = dimensions.x * dimensions.y * dimensions.z
                half_height = dimensions.y * 0.5
            elif sphere_shape != null:
                var radius: float = sphere_shape.radius
                volume = (4.0 / 3.0) * PI * pow(radius, 3)
                half_height = radius
            break
    body.set_meta("lab_volume", volume)
    body.set_meta("lab_half_height", half_height)
    return Vector2(volume, half_height)


func _physics_process(delta: float) -> void:
    _wave_phase += delta
    if _request_pick and _dragging:
        _pick()
    if _request_push:
        _request_push = false
        _push_target()
    if _request_blast:
        _explode()
    if _dragging and is_instance_valid(_held) and not _held.freeze:
        var viewport := _camera.get_viewport()
        var pos := viewport.get_mouse_position()
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            pos = viewport.get_visible_rect().size * 0.5
        var target: Vector3 = _camera.project_ray_origin(pos) + _camera.project_ray_normal(pos) * _held_distance
        var force: Vector3 = (target - _held.global_position) * DRAG_STIFFNESS - _held.linear_velocity * DRAG_DAMPING
        _held.apply_central_force(force.limit_length(900.0) * _held.mass)
    _apply_water()
    _apply_wind_and_magnet()


func _apply_water() -> void:
    for node in _water.get_overlapping_bodies():
        if not node is RigidBody3D:
            continue
        var body := node as RigidBody3D
        if body.freeze:
            continue
        var properties := _fluid_properties(body)
        var surface := _water_height
        if _waves:
            surface += 0.22 * sin(_wave_phase * 2.5 + body.global_position.x * 0.8)
        var center_y := body.global_position.y
        var height := maxf(0.01, properties.y * 2.0)
        var submerged := clampf((surface - center_y + properties.y) / height, 0.0, 1.0)
        if submerged <= 0.0:
            continue
        var buoyant_force := Vector3.UP * (9.8 * _fluid_density * properties.x * submerged)
        body.apply_central_force(buoyant_force)
        var water_relative: Vector3 = body.linear_velocity - Vector3(_water_current, 0, 0)
        # Quadratic drag approximation with bounded magnitude.
        var resistance := -water_relative * water_relative.length() * 0.9 * submerged
        body.apply_central_force(resistance.limit_length(300.0 * body.mass))
        body.apply_torque(-body.angular_velocity * 2.5 * submerged)


func _apply_wind_and_magnet() -> void:
    if not _wind_on and not _magnet_on:
        return
    var direction := Vector3(cos(_wind_angle), 0, sin(_wind_angle))
    var wind_gust := 0.78 + 0.22 * sin(_wave_phase * 1.8)
    for node in get_tree().get_nodes_in_group("demo_dynamic"):
        if not node is RigidBody3D:
            continue
        var body := node as RigidBody3D
        if body.freeze:
            continue
        if _wind_on:
            body.apply_central_force(direction * _wind_strength * body.mass * wind_gust)
        if _magnet_on and body.is_in_group("lab_metal"):
            var offset := MAGNET_POSITION - body.global_position
            var dist := offset.length()
            if dist > 0.5 and dist < 12.0:
                var strength := 550.0 * body.mass / maxf(dist * dist, 4.0)
                body.apply_central_force(offset / dist * minf(strength, 240.0 * body.mass) * (-1.0 if _magnet_repels else 1.0))
