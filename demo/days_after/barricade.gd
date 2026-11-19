extends StaticBody3D
## An original modular shelter barrier that infected may damage.

signal destroyed(slot: int)

const MAX_HEALTH := 100.0

var slot_index := -1
var health := MAX_HEALTH


func _ready() -> void:
    collision_layer = 1
    collision_mask = 0
    add_to_group("shelter_barricades")

    var box := BoxShape3D.new()
    box.size = Vector3(2.0, 1.6, 0.45)
    var collider := CollisionShape3D.new()
    collider.shape = box
    add_child(collider)

    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = box.size
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#735535")
    material.roughness = 0.95
    visual.material_override = material
    add_child(visual)


func take_damage(amount: float) -> void:
    if health <= 0.0 or not is_finite(amount) or amount <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        destroyed.emit(slot_index)
        queue_free()
