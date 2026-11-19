extends Area3D
## A simple physical target for the player's camera ray.

@export_enum("food", "water", "scrap") var resource_type: String = "food"
@export_range(1, 99, 1) var amount: int = 1
var _collected: bool = false


func collect() -> Dictionary:
    if _collected:
        return {}
    _collected = true
    visible = false
    collision_layer = 0
    return {"type": resource_type, "amount": amount}


func restore_collected(collected: bool) -> void:
    _collected = collected
    visible = not collected
    collision_layer = 0 if collected else 2
