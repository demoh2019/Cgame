extends Area3D
## A finite gathering node built with native Cgame collisions.

@export_enum("wood", "stone", "fiber") var resource_type: String = "wood"
@export_range(1, 20, 1) var charges: int = 3
var max_charges: int = 0


func _ready() -> void:
    max_charges = charges


func collect() -> Dictionary:
    if charges <= 0 or is_queued_for_deletion():
        return {}
    charges -= 1
    if charges == 0:
        visible = false
        collision_layer = 0
    return {"type": resource_type, "amount": 1, "gathering": true}


func restore_charges(value: int) -> void:
    charges = clampi(value, 0, max_charges)
    visible = charges > 0
    collision_layer = 2 if charges > 0 else 0
