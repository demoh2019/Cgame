extends CharacterBody3D
## Deterministic local enemy behavior; server-authoritative AI comes later.

const CHASE_DISTANCE := 11.0
const ATTACK_DISTANCE := 1.45
const MOVE_SPEED := 2.35
const DAMAGE := 9.0
const BARRICADE_DAMAGE := 18.0
const BARRICADE_ATTACK_DISTANCE := 1.8
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


func _blocking_barricade() -> StaticBody3D:
    if not is_instance_valid(target):
        return null
    var source := global_position + Vector3.UP * 0.2
    var destination := target.global_position + Vector3.UP * 0.2
    var query := PhysicsRayQueryParameters3D.create(source, destination)
    query.exclude = [get_rid()]
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    var barrier := hit.get("collider") as StaticBody3D
    if barrier != null and barrier.is_in_group("player_building"):
        return barrier
    return null


func _physics_process(delta: float) -> void:
    if not is_instance_valid(target):
        return
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    var difference := target.global_position - global_position
    difference.y = 0.0
    var distance := difference.length()
    var barrier: StaticBody3D = _blocking_barricade() if distance < CHASE_DISTANCE else null
    var barrier_distance := INF
    if barrier != null:
        var to_barrier := barrier.global_position - global_position
        to_barrier.y = 0.0
        barrier_distance = to_barrier.length()
    var movement := Vector3.ZERO
    if distance > ATTACK_DISTANCE and distance < CHASE_DISTANCE and barrier_distance > BARRICADE_ATTACK_DISTANCE:
        movement = difference.normalized()
        rotation.y = atan2(-movement.x, -movement.z)
    velocity.x = movement.x * MOVE_SPEED
    velocity.z = movement.z * MOVE_SPEED
    velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
    move_and_slide()
    if attack_cooldown > 0.0:
        return
    var world := get_parent()
    if barrier != null and barrier_distance <= BARRICADE_ATTACK_DISTANCE:
        attack_cooldown = 1.1
        if world != null and world.has_method("receive_barricade_hit"):
            world.call("receive_barricade_hit", barrier, BARRICADE_DAMAGE)
    elif distance <= ATTACK_DISTANCE:
        attack_cooldown = 1.1
        if world != null and world.has_method("receive_zombie_hit"):
            world.call("receive_zombie_hit", DAMAGE)
