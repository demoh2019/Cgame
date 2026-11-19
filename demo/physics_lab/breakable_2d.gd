extends RigidBody2D
## Four-way scripted shatter from a contact; not a continuum fracture solver.

@export var break_speed: float = 350.0

var _broken := false


func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 8
    body_entered.connect(_on_impact)


func _on_impact(other: Node) -> void:
    if _broken:
        return
    var speed := linear_velocity.length()
    if other is RigidBody2D:
        speed = maxf(speed, (other as RigidBody2D).linear_velocity.length())
    if speed >= break_speed:
        smash()


func smash() -> void:
    if _broken:
        return
    _broken = true
    call_deferred("_spawn_fragments")


func _spawn_fragments() -> void:
    if not is_inside_tree():
        return
    var initial_velocity := linear_velocity
    var center := global_position
    for index in range(4):
        var x := -1.0 if (index % 2) == 0 else 1.0
        var y := -1.0 if index < 2 else 1.0
        var delta := Vector2(x, y) * 12.0
        var piece := RigidBody2D.new()
        piece.name = "Fragment2D"
        piece.position = center + delta
        piece.mass = mass * 0.25
        piece.linear_velocity = initial_velocity
        piece.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
        var collision := CollisionShape2D.new()
        var shape := RectangleShape2D.new()
        shape.size = Vector2.ONE * 22.0
        collision.shape = shape
        piece.add_child(collision)
        var polygon := Polygon2D.new()
        polygon.polygon = PackedVector2Array([
            Vector2(-11, -11), Vector2(11, -11),
            Vector2(11, 11), Vector2(-11, 11)
        ])
        polygon.color = Color("#f4b57d")
        piece.add_child(polygon)
        get_parent().add_child(piece)
        piece.add_to_group("demo_dynamic_2d")
        piece.apply_central_impulse(delta.normalized() * 180.0 * piece.mass)
    queue_free()
