extends CharacterBody3D
## Deterministic local enemy behavior; server-authoritative AI comes later.

const CHASE_DISTANCE := 11.0
const ATTACK_DISTANCE := 1.45
const MOVE_SPEED := 2.35
const DAMAGE := 9.0
const GRAVITY := 24.0

var target: CharacterBody3D
var health := 36.0
var attack_cooldown := 0.0


func take_damage(amount: float) -> bool:
    health -= maxf(0.0, amount)
    if health <= 0.0:
        queue_free()
        return true
    return false


func _physics_process(delta: float) -> void:
    if not is_instance_valid(target):
        return
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    var difference := target.global_position - global_position
    difference.y = 0.0
    var distance := difference.length()
    var movement := Vector3.ZERO
    if distance > ATTACK_DISTANCE and distance < CHASE_DISTANCE:
        movement = difference.normalized()
        rotation.y = atan2(-movement.x, -movement.z)
    velocity.x = movement.x * MOVE_SPEED
    velocity.z = movement.z * MOVE_SPEED
    velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
    move_and_slide()
    if distance <= ATTACK_DISTANCE and attack_cooldown <= 0.0:
        attack_cooldown = 1.1
        var world := get_parent()
        if world != null and world.has_method("receive_zombie_hit"):
            world.call("receive_zombie_hit", DAMAGE)
