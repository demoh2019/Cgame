extends Node2D

@export var speed: float = 120.0

func _process(delta: float) -> void:
	var dir := Input.get_axis("ui_left", "ui_right")
	position.x += dir * speed * delta
