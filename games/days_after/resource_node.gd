extends Area3D
## A finite gathering node built with native Cgame collisions.

@export_enum("wood", "stone", "fiber") var resource_type: String = "wood"
@export_range(1, 20, 1) var charges: int = 3


func collect() -> Dictionary:
    if charges <= 0 or is_queued_for_deletion():
        return {}
    charges -= 1
    if charges == 0:
        queue_free()
    return {"type": resource_type, "amount": 1, "gathering": true}
