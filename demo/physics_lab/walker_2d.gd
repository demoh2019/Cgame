extends CharacterBody2D
## A simple autonomous character-controller test for collision and move_and_slide.
## It walks back and forth on the floor and reverses after wall collisions.

@export var walking_speed := 130.0
@export var gravity_acceleration := 980.0

var direction := 1.0


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y += gravity_acceleration * delta
    else:
        velocity.y = 0.0
    velocity.x = direction * walking_speed
    move_and_slide()
    if is_on_wall():
        direction *= -1.0
    # Prevent the demonstration character from wandering out of its station.
    if global_position.x > 1020:
        direction = -1.0
    elif global_position.x < 630:
        direction = 1.0
