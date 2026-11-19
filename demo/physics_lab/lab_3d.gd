extends Node3D
## Standalone interactive regression playground. Nothing in this project is
## installed into the editor or enabled in other games.

const LAB_2D := "res://lab_2d.tscn"
const INTERACTIVE_ENV_3D = preload("res://environment_3d.gd")
const ADVANCED_PHYSICS_3D = preload("res://advanced_3d.gd")
const ZONES_X := [-28.0, -14.0, 0.0, 14.0, 28.0]

var _camera: Camera3D
var _hud_stats: Label
var _hud_event: Label
var _ray: RayCast3D
var _shape_cast: ShapeCast3D
var _vehicle: VehicleBody3D
var _yaw := 0.0
var _pitch := 0.0
var _stat_timer := 0.0
var _projectile_index := 0
var _sensor_hits := 0
var _camera_station := -1


func _ready() -> void:
    _make_environment()
    _make_floor_and_zones()
    _make_rigid_stack()
    _make_ramp()
    _make_joints()
    _make_soft_body()
    _make_ccd_station()
    _make_material_station()
    _make_vehicle()
    _make_sensor_station()
    _make_camera()
    _make_hud()
    var interactions = INTERACTIVE_ENV_3D.new()
    interactions.name = "Environment3D"
    add_child(interactions)
    interactions.setup(_camera)
    var advanced = ADVANCED_PHYSICS_3D.new()
    advanced.name = "AdvancedPhysics3D"
    add_child(advanced)
    advanced.setup()


func _make_environment() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.065, 0.09, 0.14)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.72, 0.79, 1.0)
    env.ambient_light_energy = 0.75
    world.environment = env
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
    sun.light_energy = 1.1
    sun.shadow_enabled = true
    add_child(sun)


func _material(color: Color, transparent := false) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.72
    if transparent:
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return mat


func _visual_box(parent: Node3D, size: Vector3, color: Color) -> void:
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    visual.mesh = mesh
    visual.material_override = _material(color, color.a < 0.99)
    parent.add_child(visual)


func _box_collision(parent: CollisionObject3D, size: Vector3) -> void:
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    parent.add_child(collision)


func _static_box(name: String, pos: Vector3, size: Vector3, color: Color, roll := 0.0) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = name
    body.position = pos
    body.rotation.z = roll
    _box_collision(body, size)
    _visual_box(body, size, color)
    add_child(body)
    return body


func _rigid_box(pos: Vector3, size: Vector3, color: Color, mass := 1.0) -> RigidBody3D:
    var body := RigidBody3D.new()
    body.name = "DynamicBox"
    body.position = pos
    body.mass = mass
    _box_collision(body, size)
    _visual_box(body, size, color)
    add_child(body)
    body.add_to_group("demo_dynamic")
    return body


func _rigid_ball(pos: Vector3, radius: float, color: Color, mass := 1.0, ccd := false) -> RigidBody3D:
    var body := RigidBody3D.new()
    body.name = "DynamicSphere"
    body.position = pos
    body.mass = mass
    body.continuous_cd = ccd
    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = radius
    collision.shape = shape
    body.add_child(collision)
    var visual := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    visual.mesh = mesh
    visual.material_override = _material(color)
    body.add_child(visual)
    add_child(body)
    body.add_to_group("demo_dynamic")
    return body


func _station_name(x: float, z: float, caption: String) -> void:
    var label := Label3D.new()
    label.text = caption
    label.font_size = 34
    label.pixel_size = 0.012
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color(0.95, 0.97, 1.0)
    label.position = Vector3(x, 1.0, z + 7.6)
    add_child(label)


func _make_floor_and_zones() -> void:
    _static_box("Ground", Vector3(0, -0.5, 0), Vector3(94, 1, 62), Color(0.11, 0.14, 0.18))
    var names := [
        "01  Rigid stacks", "02  Ramps / rolling", "03  Joints / pendulums",
        "04  SoftBody3D", "05  Interactive water pool",
        "06  CCD projectiles", "07  Friction / restitution", "08  Vehicle suspension",
        "09  Area / ray query", "10  Magnet / wind / stress"
    ]
    var colors := [
        Color("#23455a"), Color("#284b45"), Color("#4b4059"), Color("#4c425e"), Color("#235166"),
        Color("#534039"), Color("#344f3a"), Color("#505037"), Color("#3a435e"), Color("#483f50")
    ]
    var index := 0
    for z in [-11.0, 11.0]:
        for x in ZONES_X:
            var pad := Node3D.new()
            pad.position = Vector3(x, 0.012, z)
            _visual_box(pad, Vector3(12.7, 0.023, 17.2), colors[index])
            add_child(pad)
            _station_name(x, z, names[index])
            index += 1
    _static_box("NorthWall", Vector3(0, 1.0, -31), Vector3(94, 2, 1), Color("#273444"))
    _static_box("SouthWall", Vector3(0, 1.0, 31), Vector3(94, 2, 1), Color("#273444"))
    _static_box("WestWall", Vector3(-47, 1.0, 0), Vector3(1, 2, 62), Color("#273444"))
    _static_box("EastWall", Vector3(47, 1.0, 0), Vector3(1, 2, 62), Color("#273444"))


func _make_rigid_stack() -> void:
    for layer in range(5):
        for column in range(4):
            _rigid_box(
                Vector3(-30.8 + column * 1.65, 0.6 + layer * 1.24, -11.0),
                Vector3(1.45, 1.2, 1.45),
                Color.from_hsv(0.56 + layer * 0.045, 0.55, 0.94),
                1.4
            )
    var heavy := _rigid_ball(Vector3(-28, 10, -11), 1.0, Color("#f7b456"), 8.0)
    heavy.linear_velocity = Vector3(0, -1, 0)


func _make_ramp() -> void:
    _static_box("SlopingRamp", Vector3(-14, 1.6, -11), Vector3(10.0, 0.45, 7.6), Color("#77aa94"), -0.23)
    for i in range(4):
        _rigid_ball(Vector3(-18.0, 4.0 + i * 1.8, -13.6 + i * 1.6), 0.63, Color("#f6bb61"), 2.0)


func _pin(anchor: PhysicsBody3D, bob: PhysicsBody3D, pivot: Vector3) -> void:
    var joint := PinJoint3D.new()
    joint.position = pivot
    add_child(joint)
    joint.node_a = joint.get_path_to(anchor)
    joint.node_b = joint.get_path_to(bob)


func _make_joints() -> void:
    var anchor := _static_box("PendulumAnchor", Vector3(-3, 6.5, -11), Vector3(0.7, 0.7, 0.7), Color("#d2dce9"))
    var bob := _rigid_ball(Vector3(-0.8, 3.5, -11), 0.8, Color("#eabf7a"), 4.0)
    _pin(anchor, bob, anchor.global_position)
    var last: PhysicsBody3D = _static_box("ChainAnchor", Vector3(2.2, 7, -11), Vector3(0.7, 0.7, 0.7), Color("#d2dce9"))
    for i in range(4):
        var link := _rigid_box(Vector3(2.2, 5.8 - i * 1.12, -11), Vector3(0.58, 0.95, 0.58), Color("#9fcaef"))
        _pin(last, link, Vector3(2.2, 6.55 - i * 1.12, -11))
        last = link
    var hinge_base := _static_box("HingeBase", Vector3(-3, 6, -17), Vector3(0.8, 0.8, 0.8), Color("#e2e5f0"))
    var hinge_bar := _rigid_box(Vector3(-3, 4.6, -17), Vector3(2.4, 0.42, 0.8), Color("#f2ac97"))
    var hinge := HingeJoint3D.new()
    hinge.position = hinge_base.position
    add_child(hinge)
    hinge.node_a = hinge.get_path_to(hinge_base)
    hinge.node_b = hinge.get_path_to(hinge_bar)
    var slider_base := _static_box("SliderBase", Vector3(2.3, 3, -5), Vector3(0.7, 0.7, 0.7), Color("#e2e5f0"))
    var sliding_weight := _rigid_box(Vector3(4.0, 3, -5), Vector3(0.9, 0.9, 0.9), Color("#a6d3a2"))
    var slider := SliderJoint3D.new()
    slider.position = slider_base.position
    add_child(slider)
    slider.node_a = slider.get_path_to(slider_base)
    slider.node_b = slider.get_path_to(sliding_weight)


# An indexed, watertight cube with eight SHARED vertices. A BoxMesh
# duplicates vertices per face and is unsuitable for tetra FEM cooking.
# The new conservative star tetrahedralizer produces six actual tets.
func _build_fem_convex_cube() -> ArrayMesh:
    var vertices := PackedVector3Array([
        Vector3(-1.2, -1.2, -1.2), Vector3(1.2, -1.2, -1.2),
        Vector3(1.2, 1.2, -1.2), Vector3(-1.2, 1.2, -1.2),
        Vector3(-1.2, -1.2, 1.2), Vector3(1.2, -1.2, 1.2),
        Vector3(1.2, 1.2, 1.2), Vector3(-1.2, 1.2, 1.2)
    ])
    var indices := PackedInt32Array([
        0, 2, 1, 0, 3, 2,
        4, 5, 6, 4, 6, 7,
        0, 1, 5, 0, 5, 4,
        3, 7, 6, 3, 6, 2,
        0, 4, 7, 0, 7, 3,
        1, 2, 6, 1, 6, 5
    ])
    var normals := PackedVector3Array()
    for vertex in vertices:
        normals.append(vertex.normalized())
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var result := ArrayMesh.new()
    result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return result


# Five welded surface vertices and exactly two explicitly authored volume
# tetrahedra. Their union is NONCONVEX: a convex fan would reject this mesh.
# The imported connectivity is validated against the six oriented faces.
func _build_fem_concave_doubletet() -> ArrayMesh:
    var vertices := PackedVector3Array([
        Vector3(0, 0, 0), Vector3(1.6, 0, 0), Vector3(0, 1.6, 0),
        Vector3(0, 0, 1.6), Vector3(0.96, 1.28, -0.4)
    ])
    var indices := PackedInt32Array([
        1, 2, 3, 0, 3, 2, 0, 1, 3,
        2, 1, 4, 0, 4, 1, 0, 2, 4
    ])
    # SoftBodyRenderingServerHandler updates normals every frame. Supply
    # an initial packed normal attribute to keep the vertex layout valid.
    var normals := PackedVector3Array()
    normals.resize(vertices.size())
    for i in range(0, indices.size(), 3):
        var a := indices[i]
        var b := indices[i + 1]
        var c := indices[i + 2]
        var normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
        normals[a] = normals[a] + normal
        normals[b] = normals[b] + normal
        normals[c] = normals[c] + normal
    for i in range(normals.size()):
        normals[i] = normals[i].normalized()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _make_soft_body() -> void:
    var soft := SoftBody3D.new()
    soft.name = "DeformableMesh"
    var mesh := SphereMesh.new()
    mesh.radius = 1.55
    mesh.height = 3.1
    mesh.radial_segments = 16
    mesh.rings = 8
    soft.mesh = mesh
    soft.position = Vector3(11.7, 6, -11)
    soft.simulation_precision = 9
    soft.total_mass = 3.0
    soft.material_override = _material(Color("#cf9aef"))
    add_child(soft)

    # Unlike the sphere above, this indexed, closed, convex mesh has a
    # deterministic six-tetrahedral FEM interior. Other physics engines
    # may ignore the experimental GodotPhysics3D FEM extension.
    var fem_cube := SoftBody3D.new()
    fem_cube.name = "FEMConvexCubeSixTets"
    fem_cube.mesh = _build_fem_convex_cube()
    fem_cube.position = Vector3(16.6, 6, -11)
    fem_cube.simulation_precision = 12
    fem_cube.total_mass = 4.0
    fem_cube.material_override = _material(Color("#82dae7"))
    add_child(fem_cube)

    var imported := SoftBody3D.new()
    imported.name = "FEMConcaveImportedTwoTets"
    # Imported order refers to visual mesh vertex IDs, not welded Node IDs.
    imported.tetrahedral_indices = PackedInt32Array([0, 1, 2, 3, 0, 2, 1, 4])
    imported.mesh = _build_fem_concave_doubletet()
    imported.position = Vector3(19.3, 6.4, -11)
    imported.simulation_precision = 12
    imported.total_mass = 2.5
    imported.material_override = _material(Color("#f7b476"))
    add_child(imported)

    # The FEM simulation has 9 nodes: 8 on the surface + 1 interior.
    # Build 12 tetrahedra linking the interior node to each cube face.
    # The center is integrated by FEM and mass-lumping but has no BVH
    # point collider or rendering vertex.
    var inner_cube := SoftBody3D.new()
    inner_cube.name = "FEMInteriorNodeTwelveTets"
    inner_cube.tetrahedral_interior_positions = PackedVector3Array([Vector3.ZERO])
    var interior_mesh := _build_fem_convex_cube()
    var shell_triangles: PackedInt32Array = interior_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
    var tetra_indices := PackedInt32Array()
    for i in range(0, shell_triangles.size(), 3):
        tetra_indices.append_array(PackedInt32Array([
            8, shell_triangles[i], shell_triangles[i + 1], shell_triangles[i + 2]
        ]))
    inner_cube.tetrahedral_indices = tetra_indices
    inner_cube.mesh = interior_mesh
    inner_cube.position = Vector3(22.3, 6, -11)
    inner_cube.simulation_precision = 12
    inner_cube.total_mass = 4.0
    inner_cube.material_override = _material(Color("#92e4ae"))
    add_child(inner_cube)
    _static_box("SoftBodyObstacle", Vector3(16.5, 0.75, -11), Vector3(17.5, 1.5, 6), Color("#b3a9ce"))


func _make_ccd_station() -> void:
    _static_box("ThinTarget", Vector3(-28, 2, 7), Vector3(9.0, 4.0, 0.12), Color("#df8b75"))
    _launch_ccd(false)
    _launch_ccd(true)


func _launch_ccd(enabled: bool) -> void:
    _projectile_index += 1
    var x := -30.0 if enabled else -26.0
    var shot := _rigid_ball(Vector3(x, 2.6, 18.4), 0.32, Color("#8bf4f5") if enabled else Color("#f4d18b"), 1.0, enabled)
    shot.name = "CCD_%s_%d" % [str(enabled), _projectile_index]
    shot.gravity_scale = 0.0
    shot.linear_velocity = Vector3(0, 0, -110)


func _make_material_station() -> void:
    _static_box("FrictionSlope", Vector3(-14, 1.0, 11), Vector3(10, 0.25, 13), Color("#80a391"), -0.13)
    for i in range(5):
        var ball := _rigid_ball(Vector3(-17.2, 3.2 + i * 1.2, 6 + i * 2.0), 0.48, Color("#efcd85"))
        var phys := PhysicsMaterial.new()
        phys.friction = float(i) * 0.24
        phys.bounce = float(i) * 0.18
        ball.physics_material_override = phys


func _make_vehicle() -> void:
    _vehicle = VehicleBody3D.new()
    _vehicle.name = "SuspensionVehicle"
    _vehicle.position = Vector3(0, 2.7, 18)
    _vehicle.mass = 90.0
    _vehicle.engine_force = 330.0
    _box_collision(_vehicle, Vector3(2.3, 0.85, 3.4))
    _visual_box(_vehicle, Vector3(2.3, 0.85, 3.4), Color("#f0ac72"))
    for side in [-1.0, 1.0]:
        for front in [true, false]:
            var wheel := VehicleWheel3D.new()
            wheel.position = Vector3(side * 1.05, -0.45, -1.22 if front else 1.22)
            wheel.wheel_radius = 0.47
            wheel.wheel_rest_length = 0.34
            wheel.use_as_steering = front
            wheel.use_as_traction = not front
            _vehicle.add_child(wheel)
            var rim := MeshInstance3D.new()
            var tire := CylinderMesh.new()
            tire.top_radius = 0.47
            tire.bottom_radius = 0.47
            tire.height = 0.27
            rim.mesh = tire
            rim.rotation.z = PI * 0.5
            rim.material_override = _material(Color("#252a32"))
            wheel.add_child(rim)
    add_child(_vehicle)
    _vehicle.add_to_group("demo_dynamic")
    _static_box("VehicleBump", Vector3(0, 0.3, 7), Vector3(5, 0.6, 2), Color("#c8c09c"))


func _make_sensor_station() -> void:
    var sensor := Area3D.new()
    sensor.name = "BodyEnterSensor"
    sensor.position = Vector3(14, 2.4, 11)
    sensor.collision_layer = 0
    sensor.collision_mask = 1
    sensor.monitoring = true
    _box_collision(sensor, Vector3(7, 4.5, 8))
    add_child(sensor)
    sensor.body_entered.connect(_on_sensor_entered)
    var mark := Node3D.new()
    mark.position = sensor.position
    _visual_box(mark, Vector3(7, 4.5, 8), Color(0.42, 0.78, 1.0, 0.12))
    add_child(mark)
    for i in range(5):
        _rigid_box(Vector3(12 + i, 7 + i * 1.3, 11), Vector3.ONE, Color("#a9d3ed"))
    _ray = RayCast3D.new()
    _ray.name = "DownwardQuery"
    _ray.position = Vector3(14, 10, 11)
    _ray.target_position = Vector3(0, -14, 0)
    _ray.enabled = true
    add_child(_ray)
    _shape_cast = ShapeCast3D.new()
    _shape_cast.name = "DownwardShapeCast"
    _shape_cast.position = Vector3(16.5, 10, 11)
    var cast_shape := SphereShape3D.new()
    cast_shape.radius = 0.55
    _shape_cast.shape = cast_shape
    _shape_cast.target_position = Vector3(0, -14, 0)
    _shape_cast.enabled = true
    add_child(_shape_cast)


func _make_camera() -> void:
    _camera = Camera3D.new()
    _camera.position = Vector3(0, 24, 47)
    _camera.fov = 76.0
    add_child(_camera)
    _camera.look_at(Vector3(0, 3, 0), Vector3.UP)
    _yaw = _camera.rotation.y
    _pitch = _camera.rotation.x


func _make_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(14, 14)
    panel.custom_minimum_size = Vector2(480, 0)
    layer.add_child(panel)
    var margin := MarginContainer.new()
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 11)
    panel.add_child(margin)
    var content := VBoxContainer.new()
    margin.add_child(content)
    var title := Label.new()
    title.text = "CGAME | 3D PHYSICS LAB"
    title.add_theme_font_size_override("font_size", 21)
    content.add_child(title)
    var instructions := Label.new()
    instructions.text = "ПКМ: обзор камерой  |  WASD + Q/E: полёт  |  Shift: быстро\nB: бросить куб  |  C: две CCD-пули  |  Space: импульс\nX: +100 тел | стрелки: машина | Ctrl: тормоз\nF1: 2D | R: сброс\nEsc: освободить курсор"
    content.add_child(instructions)
    _hud_stats = Label.new()
    content.add_child(_hud_stats)
    _hud_event = Label.new()
    _hud_event.text = "События Area3D появятся здесь."
    content.add_child(_hud_event)
    var buttons := HBoxContainer.new()
    content.add_child(buttons)
    var open_2d := Button.new()
    open_2d.text = "Открыть 2D [F1]"
    open_2d.pressed.connect(func() -> void: get_tree().change_scene_to_file(LAB_2D))
    buttons.add_child(open_2d)
    var reset := Button.new()
    reset.text = "Сброс [R]"
    reset.pressed.connect(func() -> void: get_tree().reload_current_scene())
    buttons.add_child(reset)
    var stress := Button.new()
    stress.text = "Стресс +100 [X]"
    stress.pressed.connect(_spawn_stress)
    buttons.add_child(stress)


func _on_sensor_entered(body: Node3D) -> void:
    if body is RigidBody3D:
        _sensor_hits += 1
        if _hud_event != null:
            _hud_event.text = "Area3D: %s | пересечений: %d" % [body.name, _sensor_hits]


func _spawn_box_from_camera() -> void:
    var forward := -_camera.global_transform.basis.z
    var body := _rigid_box(_camera.global_position + forward * 5.0, Vector3.ONE * 1.1, Color("#fdcc7c"), 3.0)
    body.linear_velocity = forward * 18.0


func _spawn_stress() -> void:
    # Fixed batch keeps the action repeatable and gives the user control of load.
    for i in range(100):
        var col := i % 10
        var row := (i / 10) % 10
        _rigid_box(
            Vector3(23.4 + col * 0.95, 3.0 + row * 1.06, 7.1 + (i % 7) * 0.9),
            Vector3.ONE * 0.8,
            Color("#c7a9dd"),
            0.8
        )


func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        if event.pressed:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        else:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _yaw -= event.relative.x * 0.003
        _pitch = clampf(_pitch - event.relative.y * 0.003, -1.45, 1.45)
        _camera.rotation = Vector3(_pitch, _yaw, 0)
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_TAB:
                _cycle_camera_station()
            KEY_ESCAPE:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            KEY_F1:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
                get_tree().change_scene_to_file(LAB_2D)
            KEY_R:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
                get_tree().reload_current_scene()
            KEY_B:
                _spawn_box_from_camera()
            KEY_C:
                _launch_ccd(false)
                _launch_ccd(true)
            KEY_X:
                _spawn_stress()
            KEY_SPACE:
                for body in get_tree().get_nodes_in_group("demo_dynamic"):
                    if body is RigidBody3D:
                        body.apply_central_impulse(Vector3(0, body.mass * 3, 0))


func _process(delta: float) -> void:
    var move := Vector3.ZERO
    if Input.is_key_pressed(KEY_W):
        move.z -= 1.0
    if Input.is_key_pressed(KEY_S):
        move.z += 1.0
    if Input.is_key_pressed(KEY_A):
        move.x -= 1.0
    if Input.is_key_pressed(KEY_D):
        move.x += 1.0
    if Input.is_key_pressed(KEY_Q):
        move.y -= 1.0
    if Input.is_key_pressed(KEY_E):
        move.y += 1.0
    if move.length_squared() > 0:
        var speed := 36.0 if Input.is_key_pressed(KEY_SHIFT) else 15.0
        _camera.position += (_camera.global_transform.basis * move.normalized()) * speed * delta
    _stat_timer += delta
    if _stat_timer >= 0.4:
        _stat_timer = 0
        var count := get_tree().get_nodes_in_group("demo_dynamic").size()
        var hit := str(_ray.get_collider().name) if _ray.is_colliding() else "нет"
        _hud_stats.text = "FPS: %d | Bodies: %d | Ray: %s | ShapeCast: %s" % [Engine.get_frames_per_second(), count, hit, str(_shape_cast.is_colliding())]


func _cycle_camera_station() -> void:
    var targets := [
        Vector3(0, 2.0, -11.0),
        Vector3(28, 2.0, -11.0),
        Vector3(-21, 2.5, 24.0),
        Vector3(4, 3.0, 24.0),
        Vector3(28, 2.5, 11.0)
    ]
    _camera_station = (_camera_station + 1) % targets.size()
    var at: Vector3 = targets[_camera_station]
    _camera.position = at + Vector3(11, 13, 19)
    _camera.look_at(at, Vector3.UP)
    _yaw = _camera.rotation.y
    _pitch = _camera.rotation.x


func _physics_process(delta: float) -> void:
    # Keyboard drive only affects the demo vehicle (and does not touch camera keys).
    if _vehicle == null:
        return
    var throttle := (1.0 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)
    var steering_target := ((1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0)) * 0.4
    _vehicle.engine_force = throttle * 1100.0
    _vehicle.steering = move_toward(_vehicle.steering, steering_target, delta * 1.7)
    _vehicle.brake = 90.0 if Input.is_key_pressed(KEY_CTRL) else 0.0
