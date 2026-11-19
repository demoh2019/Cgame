extends Node3D

## Procedural ribbon with three-node XPBD curvature constraints along its
## original structural edges. This is rod-like BENDING, not Cosserat twist.

const SEGMENTS := 20
const LENGTH := 6.0
const WIDTH := 0.22

var impact_ball: RigidBody3D


func _ready() -> void:
    _add_world()
    _add_curved_ribbon()
    _add_impact_ball()
    _add_hud()


func _material(color: Color) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.roughness = 0.62
    result.cull_mode = BaseMaterial3D.CULL_DISABLED
    return result


func _add_world() -> void:
    var camera := Camera3D.new()
    camera.position = Vector3(7.0, 1.3, 11.0)
    add_child(camera)
    camera.look_at(Vector3(0, -1.7, 0))
    camera.current = true
    var light := DirectionalLight3D.new()
    light.rotation = Vector3(-0.9, -0.4, 0.0)
    add_child(light)
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#1c2333")
    world.environment = environment
    add_child(world)


func _create_ribbon_mesh() -> ArrayMesh:
    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    for i in range(SEGMENTS + 1):
        var t := float(i) / float(SEGMENTS)
        var bend := sin(t * PI) * 0.65
        for side in range(2):
            var x := bend + (-0.5 if side == 0 else 0.5) * WIDTH
            verts.append(Vector3(x, 1.8 - LENGTH * t, 0))
            normals.append(Vector3(0, 0, 1))
    for i in range(SEGMENTS):
        var a := 2 * i
        var b := a + 1
        var c := a + 2
        var d := a + 3
        indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _add_curved_ribbon() -> void:
    var ribbon := SoftBody3D.new()
    ribbon.name = "CurvedRodRibbon"
    ribbon.mesh = _create_ribbon_mesh()
    ribbon.total_mass = 5.0
    ribbon.simulation_precision = 16
    ribbon.material_override = _material(Color("#f1d18b"))
    add_child(ribbon)
    # Two top vertices form the anchored end of the beam.
    ribbon.pin_point(0, true)
    ribbon.pin_point(1, true)


func _add_impact_ball() -> void:
    impact_ball = RigidBody3D.new()
    impact_ball.name = "ImpactBall"
    impact_ball.position = Vector3(-3.0, -1.2, 0)
    impact_ball.mass = 2.0
    impact_ball.contact_monitor = true
    impact_ball.max_contacts_reported = 6
    var collider := CollisionShape3D.new()
    var sphere := SphereShape3D.new()
    sphere.radius = 0.42
    collider.shape = sphere
    impact_ball.add_child(collider)
    var visible := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 0.42
    mesh.height = 0.84
    visible.mesh = mesh
    visible.material_override = _material(Color("#83c1f5"))
    impact_ball.add_child(visible)
    add_child(impact_ball)


func _add_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(16, 16)
    layer.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(margin)
    var label := Label.new()
    label.text = "Cgame Discrete Rod Curvature Lab\nCurved soft ribbon: XPBD centerline angle + stretch\nSpace: launch blue impact ball | R: restart | Esc: quit\nCompare rod_bend_compliance=0 and 0.000003 in project.godot\nRod bending is native C++, not GDScript. No twist directors yet."
    margin.add_child(label)


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE and impact_ball != null:
            impact_ball.apply_central_impulse(Vector3(7.0, 1.0, 0.0))
        elif event.keycode == KEY_R:
            get_tree().reload_current_scene()
        elif event.keycode == KEY_ESCAPE:
            get_tree().quit()
