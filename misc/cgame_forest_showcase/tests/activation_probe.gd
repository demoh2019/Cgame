extends Node3D
## Tiny PackedScene root for testing native cell-activation readiness.
## A loaded and physics-stabilized root is NOT automatically gameplay-ready.

var allow_activation: bool = false
var physics_ticks: int = 0


func _physics_process(_delta: float) -> void:
    physics_ticks += 1


func is_streaming_activation_ready() -> bool:
    return allow_activation
