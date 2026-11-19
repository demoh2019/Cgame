extends Node2D
## 2D interactive force playground. The pool is an empirical buoyancy/drag
## demonstration, not an SPH/FLIP particle-liquid simulation.

const POOL_X := -690.0
const POOL_BOTTOM := 420.0
const POOL_WIDTH := 330.0
const MAGNET_POSITION := Vector2(765.0, 140.0)

var _water: Area2D
var _water_shape: RectangleShape2D
var _water_visual: Polygon2D
var _status: Label
var _water_depth := 245.0
var _fluid_density := 0.001
var _flow := 60.0
var _wind_on := false
var _wind_force := 350.0
var _wind_angle := 0.0
var _magnet_on := false
var _gravity_scale := 1.0
var _spawn_mass := 2.0
var _wave_phase := 0.0
var _waves := true
var _held: RigidBody2D
var _dragging := false
var _request_pick := false
var _request_push := false
var _request_blast := false
var _mouse_world := Vector2.ZERO


func setup() -> void:
    _make_pool()
    _make_magnet()
    _make_hud()
    spawn_water_body(false)
    spawn_water_body(true)
    _update_status()


func _rect_vertices(size: Vector2) -> PackedVector2Array:
    var half := size / 2.0
    return PackedVector2Array([
        Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
        Vector2(half.x, half.y), Vector2(-half.x, half.y)
    ])


func _make_pool() -> void:
    _water = Area2D.new()
    _water.name = "WaterVolume2D"
    _water.collision_layer = 0
    _water.collision_mask = 1
    _water.monitoring = true
    add_child(_water)
    var collider := CollisionShape2D.new()
    _water_shape = RectangleShape2D.new()
    collider.shape = _water_shape
    _water.add_child(collider)
    _water_visual = Polygon2D.new()
    _water_visual.color = Color(0.14, 0.62, 0.94, 0.30)
    _water.add_child(_water_visual)
    _set_depth(_water_depth)
    _static_wall("PoolWallLeft", Vector2(POOL_X - POOL_WIDTH / 2.0, 270), Vector2(12, 295))
    _static_wall("PoolWallRight", Vector2(POOL_X + POOL_WIDTH / 2.0, 270), Vector2(12, 295))
    var name := Label.new()
    name.name = "PoolLabel"
    name.text = "WATER: buoyancy, current, drag"
    name.position = Vector2(POOL_X - 165, 70)
    name.add_theme_font_size_override("font_size", 19)
    add_child(name)


func _static_wall(title: String, pos: Vector2, size: Vector2) -> void:
    var body := StaticBody2D.new()
    body.name = title
    body.position = pos
    var collider := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    var mesh := Polygon2D.new()
    mesh.polygon = _rect_vertices(size)
    mesh.color = Color("#83bad3")
    body.add_child(mesh)
    add_child(body)


func _set_depth(depth: float) -> void:
    _water_depth = clampf(depth, 65.0, 300.0)
    var size := Vector2(POOL_WIDTH, _water_depth)
    _water_shape.size = size
    _water_visual.polygon = _rect_vertices(size)
    _water.position = Vector2(POOL_X, POOL_BOTTOM - _water_depth / 2.0)
    _update_status()


func _make_magnet() -> void:
    var magnet := Polygon2D.new()
    magnet.name = "Magnet2D"
    magnet.position = MAGNET_POSITION
    magnet.polygon = _rect_vertices(Vector2(60, 60))
    magnet.color = Color("#f18ca7")
    add_child(magnet)
    var label := Label.new()
    label.text = "MAGNET [M]"
    label.position = MAGNET_POSITION + Vector2(-85, -100)
    label.add_theme_font_size_override("font_size", 18)
    add_child(label)
    for i in range(5):
        var metal := _new_body(Vector2(720 + (i % 3) * 70, -200 - i * 35), 18, 1.5, true)
        metal.name = "Metal2D"


func _new_body(position_2d: Vector2, radius: float, mass: float, metal := false) -> RigidBody2D:
    var body := RigidBody2D.new()
    body.name = "MetalSphere2D" if metal else "WaterSphere2D"
    body.position = position_2d
    body.mass = maxf(0.1, mass)
    body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
    var collider := CollisionShape2D.new()
    var shape := CircleShape2D.new()
    shape.radius = radius
    collider.shape = shape
    body.add_child(collider)
    var visual := Polygon2D.new()
    var vertices := PackedVector2Array()
    for step in range(32):
        vertices.append(Vector2.RIGHT.rotated(TAU * float(step) / 32.0) * radius)
    visual.polygon = vertices
    visual.color = Color("#f8b0c4") if metal else Color("#9bf0cd")
    body.add_child(visual)
    get_parent().add_child(body)
    body.add_to_group("demo_dynamic_2d")
    if metal:
        body.add_to_group("lab_metal_2d")
    body.set_meta("lab_area", PI * radius * radius)
    body.set_meta("lab_half_height", radius)
    body.gravity_scale = _gravity_scale
    return body


func spawn_water_body(heavy: bool) -> void:
    var body := _new_body(
        Vector2(POOL_X + (55.0 if heavy else -55.0), -130.0),
        25.0, 16.0 if heavy else _spawn_mass
    )
    body.name = "HeavySinker2D" if heavy else "LightFloater2D"


func _make_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "InteractionHUD2D"
    add_child(layer)
    var panel := PanelContainer.new()
    panel.anchor_left = 1.0
    panel.anchor_right = 1.0
    panel.offset_left = -365.0
    panel.offset_right = -12.0
    panel.offset_top = 12.0
    layer.add_child(panel)
    var margin := MarginContainer.new()
    panel.add_child(margin)
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 9)
    var col := VBoxContainer.new()
    margin.add_child(col)
    var title := Label.new()
    title.text = "INTERACTIONS | 2D"
    title.add_theme_font_size_override("font_size", 19)
    col.add_child(title)
    var help := Label.new()
    help.text = "ЛКМ: тащить | F: толкнуть | P: взрыв\nV: ветер | T: направление | M: магнит\nO: сбросить в воду | J/U: глубина | Y: волны\nK: гравитация | Z: заморозить захваченное"
    col.add_child(help)
    _status = Label.new()
    col.add_child(_status)
    _slider(col, "Ветер", 0.0, 1500.0, _wind_force, func(v: float) -> void:
        _wind_force = v
        _update_status()
    )
    _slider(col, "Глубина воды", 65.0, 300.0, _water_depth, func(v: float) -> void:
        _set_depth(v)
    )
    _slider(col, "Плотность воды", 0.0002, 0.012, _fluid_density, func(v: float) -> void:
        _fluid_density = v
        _update_status()
    )
    _slider(col, "Течение воды", -180.0, 180.0, _flow, func(v: float) -> void:
        _flow = v
        _update_status()
    )
    _slider(col, "Масса нового шара", 0.5, 25.0, _spawn_mass, func(v: float) -> void:
        _spawn_mass = v
        _update_status()
    )
    var row1 := HBoxContainer.new()
    col.add_child(row1)
    _button(row1, "Лёгкий", func() -> void: spawn_water_body(false))
    _button(row1, "Тяжёлый", func() -> void: spawn_water_body(true))
    _button(row1, "Взрыв", func() -> void: _request_blast = true)
    var row2 := HBoxContainer.new()
    col.add_child(row2)
    _button(row2, "Ветер", _toggle_wind)
    _button(row2, "Магнит", _toggle_magnet)
    _button(row2, "Волны", _toggle_waves)
    var row3 := HBoxContainer.new()
    col.add_child(row3)
    _button(row3, "Гравитация", _cycle_gravity)
    _button(row3, "Повернуть ветер", _rotate_wind)


func _slider(col: VBoxContainer, label_text: String, min_value: float, max_value: float, initial: float, callback: Callable) -> void:
    var label := Label.new()
    label.text = label_text
    col.add_child(label)
    var slider := HSlider.new()
    slider.min_value = min_value
    slider.max_value = max_value
    slider.step = 0.0001 if max_value < 1.0 else 0.1
    slider.value = initial
    col.add_child(slider)
    slider.value_changed.connect(callback)


func _button(row: HBoxContainer, name: String, callback: Callable) -> void:
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
    if is_equal_approx(_gravity_scale, 1.0):
        _gravity_scale = 0.0
    elif is_zero_approx(_gravity_scale):
        _gravity_scale = -0.6
    else:
        _gravity_scale = 1.0
    for node in get_tree().get_nodes_in_group("demo_dynamic_2d"):
        if node is RigidBody2D:
            node.gravity_scale = _gravity_scale
    _update_status()


func _toggle_freeze() -> void:
    if is_instance_valid(_held):
        _held.freeze = not _held.freeze
        if _held.freeze:
            _held = null
            _dragging = false


func _update_status() -> void:
    if _status == null:
        return
    _status.text = "Вода: %.0fpx | ρ: %.4f | течение: %.0f | ветер: %s %.0f\nМагнит: %s | g: %.1f | волны: %s" % [
        _water_depth, _fluid_density, _flow, "ON" if _wind_on else "OFF", _wind_force,
        "ON" if _magnet_on else "OFF", _gravity_scale, "ON" if _waves else "OFF"
    ]


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _mouse_world = get_global_mouse_position()
            _request_pick = true
            _dragging = true
        else:
            _held = null
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
            KEY_Y:
                _toggle_waves()
            KEY_O:
                spawn_water_body(false)
            KEY_J:
                _set_depth(_water_depth - 20.0)
            KEY_U:
                _set_depth(_water_depth + 20.0)
            KEY_K:
                _cycle_gravity()
            KEY_Z:
                _toggle_freeze()


func _pick_body() -> RigidBody2D:
    var params := PhysicsPointQueryParameters2D.new()
    params.position = _mouse_world
    params.collision_mask = 1
    params.collide_with_areas = false
    for hit in get_world_2d().direct_space_state.intersect_point(params):
        var body := hit["collider"] as RigidBody2D
        if body != null and not body.freeze:
            return body
    return null


func _physics_process(delta: float) -> void:
    _wave_phase += delta
    if _request_pick and _dragging:
        _request_pick = false
        _held = _pick_body()
        if is_instance_valid(_held):
            _held.sleeping = false
    if _request_push:
        _request_push = false
        _mouse_world = get_global_mouse_position()
        var body := _pick_body()
        if body != null:
            body.apply_central_impulse(Vector2(500, -270) * body.mass)
    if _request_blast:
        _request_blast = false
        _explode()
    if _dragging and is_instance_valid(_held) and not _held.freeze:
        var target := get_global_mouse_position()
        var force := (target - _held.global_position) * 35.0 - _held.linear_velocity * 10.0
        _held.apply_central_force(force.limit_length(8000.0) * _held.mass)
    _apply_water()
    _apply_forces()


func _explode() -> void:
    var center := get_global_mouse_position()
    for node in get_tree().get_nodes_in_group("demo_dynamic_2d"):
        if not node is RigidBody2D:
            continue
        var body := node as RigidBody2D
        if body.freeze:
            continue
        var offset := body.global_position - center
        var distance := offset.length()
        if distance > 0.1 and distance < 320.0:
            var intensity := 1150.0 * pow(1.0 - distance / 320.0, 2)
            body.apply_central_impulse(offset / distance * intensity * body.mass)


func _body_properties(body: RigidBody2D) -> Vector2:
    if body.has_meta("lab_area"):
        return Vector2(float(body.get_meta("lab_area")), float(body.get_meta("lab_half_height")))
    var area := 1500.0
    var half_height := 22.0
    for node in body.get_children():
        if node is CollisionShape2D:
            var circle_shape := node.shape as CircleShape2D
            var rect_shape := node.shape as RectangleShape2D
            if circle_shape != null:
                var r: float = circle_shape.radius
                area = PI * r * r
                half_height = r
            elif rect_shape != null:
                var size: Vector2 = rect_shape.size
                area = size.x * size.y
                half_height = size.y / 2.0
            break
    body.set_meta("lab_area", area)
    body.set_meta("lab_half_height", half_height)
    return Vector2(area, half_height)


func _apply_water() -> void:
    var top := POOL_BOTTOM - _water_depth
    for node in _water.get_overlapping_bodies():
        if not node is RigidBody2D:
            continue
        var body := node as RigidBody2D
        if body.freeze:
            continue
        var properties := _body_properties(body)
        var level := top
        if _waves:
            level += 10.0 * sin(_wave_phase * 2.0 + body.global_position.x * 0.025)
        var submerged := clampf((body.global_position.y + properties.y - level) / (2.0 * maxf(1.0, properties.y)), 0.0, 1.0)
        if submerged <= 0.0:
            continue
        # Per-area buoyancy force and current. Density is mass per squared pixel.
        body.apply_central_force(Vector2.UP * (980.0 * _fluid_density * properties.x * submerged))
        var relative := body.linear_velocity - Vector2(_flow, 0)
        body.apply_central_force((-relative * relative.length() * 0.09 * submerged).limit_length(body.mass * 4500.0))
        body.apply_torque(-body.angular_velocity * 120.0 * submerged)


func _apply_forces() -> void:
    if not _wind_on and not _magnet_on:
        return
    var direction := Vector2.RIGHT.rotated(_wind_angle)
    var gust := 0.75 + 0.25 * sin(_wave_phase * 1.7)
    for node in get_tree().get_nodes_in_group("demo_dynamic_2d"):
        if not node is RigidBody2D:
            continue
        var body := node as RigidBody2D
        if body.freeze:
            continue
        if _wind_on:
            body.apply_central_force(direction * _wind_force * body.mass * gust)
        if _magnet_on and body.is_in_group("lab_metal_2d"):
            var toward := MAGNET_POSITION - body.global_position
            var distance := toward.length()
            if distance > 10.0 and distance < 400.0:
                body.apply_central_force(toward / distance * body.mass * 65000.0 / maxf(distance, 40.0))
