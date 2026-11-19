extends Node3D
## Test-only target for infected steering and attack occlusion.

var health: float = 100.0


func take_damage(amount: float) -> void:
    health = maxf(0.0, health - maxf(0.0, amount))
