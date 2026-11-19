extends StaticBody3D
## One-time world resource. The collider participates in the player's physics ray.

var kind := ""
var amount := 1
var caption := ""


func setup(p_kind: String, p_amount: int) -> void:
    kind = p_kind
    amount = p_amount
    caption = ("Food" if kind == "food" else "Water") + " x" + str(amount)
    name = kind.capitalize() + "Pickup"
    add_to_group("days_after_supplies")

    var shape := BoxShape3D.new()
    shape.size = Vector3(0.55, 0.6, 0.55)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    add_child(collision)

    var mesh := BoxMesh.new()
    mesh.size = shape.size
    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.36, 0.62, 0.24) if kind == "food" else Color(0.14, 0.59, 0.92)
    visual.material_override = material
    add_child(visual)


func collect(player: Node) -> void:
    if not is_queued_for_deletion() and player.has_method("add_supply") and player.call("add_supply", kind, amount):
        queue_free()
