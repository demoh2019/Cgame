extends RigidBody3D
## Scripted impact fragmentation. A visual approximation, not a fracture solver.

@export var break_speed: float = 8.0
@export var fragment_count: int = 8

var _broken := false


func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 8
    body_entered.connect(_on_impact)


func _on_impact(other: Node) -> void:
    if _broken:
        return
    var speed := linear_velocity.length()
    if other is RigidBody3D:
        speed = maxf(speed, (other as RigidBody3D).linear_velocity.length())
    if speed >= break_speed:
        smash()


func smash() -> void:
    if _broken:
        return
    _broken = true
    # Defer structural changes out of a contact callback.
    call_deferred("_spawn_fragments")


func _spawn_fragments() -> void:
    if not is_inside_tree():
        return
    var previous_velocity := linear_velocity
    var rotation_basis := global_transform.basis
    var center := global_position
    var count := clampi(fragment_count, 1, 8)
    for index in range(count):
        var x := 1.0 if (index & 1) == 1 else -1.0
        var y := 1.0 if (index & 2) == 2 else -1.0
        var z := 1.0 if (index & 4) == 4 else -1.0
        var offset := Vector3(x, y, z) * 0.44
        var piece := RigidBody3D.new()
        piece.name = "Fragment3D"
        piece.mass = mass / float(count)
        piece.continuous_cd = true
        piece.position = center + rotation_basis * offset
        piece.linear_velocity = previous_velocity
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3.ONE * 0.72
        collision.shape = shape
        piece.add_child(collision)
        var visual := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = shape.size
        visual.mesh = mesh
        var material := StandardMaterial3D.new()
        material.albedo_color = Color("#eab57f")
        visual.material_override = material
        piece.add_child(visual)
        get_parent().add_child(piece)
        piece.add_to_group("demo_dynamic")
        var kick := (offset.normalized() + Vector3.UP * 0.3) * 2.7
        piece.apply_central_impulse(kick * piece.mass)
    queue_free()
