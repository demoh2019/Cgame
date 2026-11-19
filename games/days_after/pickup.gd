extends Area3D
## A simple physical target for the player's camera ray.

@export_enum("food", "water", "scrap") var resource_type: String = "food"
@export_range(1, 99, 1) var amount: int = 1
var _collected: bool = false


func collect() -> Dictionary:
    if _collected:
        return {}
    _collected = true
    queue_free()
    return {"type": resource_type, "amount": amount}
