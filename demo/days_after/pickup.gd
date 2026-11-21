extends Area3D

signal collected_once(pickup_id: String)

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
    material.albedo_color = Color("#6db2d4") if item_type == "water" else Color("#d6a561")
    visual.material_override = material
    add_child(visual)


func interact(player: Node) -> void:
    if collected or quantity <= 0 or not player.has_method("collect_item"):
        return
    if item_type != "food" and item_type != "water":
        return
    # Never consume the pickup if the survivor could not accept the item.
    if not bool(player.call("collect_item", item_type, quantity)):
        return
    collected = true
    collected_once.emit(name)
    set_collected_state(true)


func set_collected_state(value: bool) -> void:
    # Keep the named pickup in the world for reproducible save/load.
    # Hide it and disable physics queries instead of deleting its identity.
    collected = value
    visible = not value
    set_deferred("collision_layer", 0 if value else 1)
