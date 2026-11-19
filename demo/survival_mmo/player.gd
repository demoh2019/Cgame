extends CharacterBody3D
## Minimal 3D top-down movement. Gameplay interactions are routed by the world.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.5
const GRAVITY := 24.0

var active := true
var facing := Vector3(0, 0, -1)


func facing_direction() -> Vector3:
    return facing


func _physics_process(delta: float) -> void:
    var horizontal := Vector3.ZERO
    if active:
        horizontal.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
        horizontal.z = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
    if horizontal.length_squared() > 0.0:
        horizontal = horizontal.normalized()
        facing = horizontal
        rotation.y = atan2(-horizontal.x, -horizontal.z)
    var speed := SPRINT_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
    velocity.x = horizontal.x * speed
    velocity.z = horizontal.z * speed
    velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
    move_and_slide()
