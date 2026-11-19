extends Area3D

## A single-use scavenging pickup. The world owns the instance and the player
## owns the inventory; the pickup only transfers an item once.

@export var item_type: String = "food"
@export var display_name: String = "Продукты"
@export var quantity: int = 1

var collected: bool = false


func _ready() -> void:
    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 0.85
    collision.shape = shape
    add_child(collision)

    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.7, 0.8, 0.7)
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    var colors := {
        "food": Color("#d6a561"),
        "water": Color("#6db2d4"),
        "wood": Color("#956744"),
        "stone": Color("#a2a4a0")
    }
    material.albedo_color = colors.get(item_type, Color("#aaaaaa"))
    visual.material_override = material
    add_child(visual)


func interact(player: Node) -> void:
    if collected or not player.has_method("collect_item"):
        return
    if item_type not in ["food", "water", "wood", "stone"]:
        return
    collected = true
    player.call("collect_item", item_type, quantity)
    queue_free()
