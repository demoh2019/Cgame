extends StaticBody3D
## Finite resource node. Interact with E to gather, earn XP, and exhaust it.

var kind: String = ""
var remaining := 0
var caption := ""


func setup(resource_kind: String, units: int) -> void:
    kind = resource_kind
    remaining = maxi(0, units)
    caption = kind.capitalize() + " (" + str(remaining) + ")"
    name = kind.capitalize() + "Resource"
    add_to_group("days_after_resources")

    var shape := BoxShape3D.new()
    shape.size = Vector3(0.9, 1.2, 0.9)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    add_child(collision)

    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = shape.size
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    match kind:
        "wood":
            material.albedo_color = Color(0.43, 0.26, 0.12)
        "fiber":
            material.albedo_color = Color(0.24, 0.51, 0.21)
        _:
            material.albedo_color = Color(0.49, 0.50, 0.54)
    visual.material_override = material
    add_child(visual)


func collect(player: Node) -> void:
    if remaining <= 0 or is_queued_for_deletion():
        return
    if not player.has_method("add_supply") or not player.has_method("gathering_yield"):
        return
    var yield_amount := int(player.call("gathering_yield", kind, 1))
    if yield_amount <= 0 or not bool(player.call("add_supply", kind, yield_amount)):
        return
    remaining -= 1
    caption = kind.capitalize() + " (" + str(remaining) + ")"
    if player.has_method("award_gathering"):
        player.call("award_gathering", 12)
    if remaining == 0:
        queue_free()
