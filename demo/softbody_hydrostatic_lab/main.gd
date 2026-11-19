extends Node3D
## Closed deformable hulls, with native pressure loading in GodotPhysics3D.
## No GDScript buoyancy forces are applied to these bodies.

const WATER_LEVEL := 2.0


func _ready() -> void:
    _add_environment()
    _add_pool()
    _add_soft_cubes()
    _add_open_cloth()
    _add_labels()


func _mat(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.52
    if color.a < 0.99:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _add_environment() -> void:
    var camera := Camera3D.new()
    camera.name = "Camera"
    camera.position = Vector3(13.0, 10.0, 17.0)
    camera.look_at(Vector3(0, 0.8, 0))
    camera.current = true
    add_child(camera)
    var light := DirectionalLight3D.new()
    light.name = "Sun"
    light.rotation = Vector3(-0.9, -0.5, 0)
    add_child(light)
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#1b2333")
    world.environment = environment
    add_child(world)


func _static_box(name: String, pos: Vector3, size: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = name
    body.position = pos
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    visual.mesh = mesh
    visual.material_override = _mat(Color("#758599"))
    body.add_child(visual)
    add_child(body)


func _add_pool() -> void:
    _static_box("PoolBottom", Vector3(0, -3.1, 0), Vector3(16, 0.5, 12))
    _static_box("WallWest", Vector3(-8.0, -0.2, 0), Vector3(0.45, 6.0, 12))
    _static_box("WallEast", Vector3(8.0, -0.2, 0), Vector3(0.45, 6.0, 12))
    _static_box("WallNorth", Vector3(0, -0.2, -6), Vector3(16, 6.0, 0.45))
    _static_box("WallSouth", Vector3(0, -0.2, 6), Vector3(16, 6.0, 0.45))
    var water := MeshInstance3D.new()
    water.name = "WaterVolumeVisual"
    water.position = Vector3(0, -0.5, 0)
    var water_mesh := BoxMesh.new()
    water_mesh.size = Vector3(15.55, 5.0, 11.55)
    water.mesh = water_mesh
    water.material_override = _mat(Color(0.16, 0.63, 0.94, 0.16))
    add_child(water)


func _closed_cube_mesh() -> ArrayMesh:
    # A single indexed, consistently wound closed surface is important:
    # open meshes cannot yield an Archimedes pressure integral.
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
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var normals := PackedVector3Array()
    for vertex in vertices:
        normals.append(vertex.normalized())
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


# An OPEN indexed cloth does not receive hydrostatic pressure. It still
# receives submerged hydrodynamic drag from the native C++ solver.
func _open_cloth_mesh() -> ArrayMesh:
    var points := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    const SIDE := 5
    for z in range(SIDE):
        for x in range(SIDE):
            points.append(Vector3((float(x) - 2.0) * 0.5, 0.0, (float(z) - 2.0) * 0.5))
            normals.append(Vector3.UP)
    for z in range(SIDE - 1):
        for x in range(SIDE - 1):
            var a := z * SIDE + x
            var b := a + 1
            var c := a + SIDE
            var d := c + 1
            indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = points
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _add_open_cloth() -> void:
    _add_soft("OpenClothInCurrent", Vector3(0, 1.6, 3.0),
            _open_cloth_mesh(), 2.0, Color("#f8e192"))


func _add_soft_cubes() -> void:
    # Give each independently simulated hull a distinct mesh resource.
    _add_soft("LightFloatingSoftBody", Vector3(-3.0, 2.7, 0), _closed_cube_mesh(), 6.0, Color("#92edd2"))
    _add_soft("HeavySinkingSoftBody", Vector3(3.0, 2.7, 0), _closed_cube_mesh(), 45.0, Color("#f3b196"))


func _add_soft(name: String, pos: Vector3, soft_mesh: Mesh, total_mass: float, color: Color) -> void:
    var body := SoftBody3D.new()
    body.name = name
    body.position = pos
    body.mesh = soft_mesh
    body.simulation_precision = 12
    body.total_mass = total_mass
    body.material_override = _mat(color)
    add_child(body)


func _add_labels() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(16, 16)
    layer.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_top", 10)
    margin.add_theme_constant_override("margin_bottom", 10)
    panel.add_child(margin)
    var label := Label.new()
    label.name = "WaterExplanation"
    label.text = "Cgame Native SoftBody3D Water Lab\nClosed hulls: hydrostatic pressure + current drag\nGreen: 6 kg (float) | Orange: 45 kg (sink)\nYellow: open cloth (current drag only)\nFluid: 2.5 kg/m³ | Surface y = %.1f | Flow +X at 1.5 m/s\nR: restart | Esc: quit\nWater forces come from C++, not GDScript" % WATER_LEVEL
    margin.add_child(label)


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_R:
            get_tree().reload_current_scene()
        elif event.keycode == KEY_ESCAPE:
            get_tree().quit()
