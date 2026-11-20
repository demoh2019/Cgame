extends CharacterBody3D
## Simple infected pursues the player without pathfinding (prototype only).

signal attacked_player(raw_damage: float)

const WALK_SPEED: float = 2.0
const AGGRO_DISTANCE: float = 11.0
const ATTACK_DISTANCE: float = 1.55
const ATTACK_INTERVAL: float = 1.5

var target: CharacterBody3D
var max_health: float = 55.0
var health: float = 55.0
var attack_timer: float = 0.0


func _physics_process(delta: float) -> void:
    if health <= 0.0:
        return
    attack_timer = maxf(0.0, attack_timer - delta)
    if target == null or not is_instance_valid(target) or not bool(target.get("can_move")):
        velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
    else:
        var offset := target.global_position - global_position
        var distance := Vector2(offset.x, offset.z).length()
        if distance > ATTACK_DISTANCE and distance < AGGRO_DISTANCE:
            var move_dir := Vector3(offset.x, 0.0, offset.z).normalized()
            velocity.x = move_dir.x * WALK_SPEED
            velocity.z = move_dir.z * WALK_SPEED
        else:
            velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
            velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
        if distance <= ATTACK_DISTANCE and attack_timer <= 0.0:
            attack_timer = ATTACK_INTERVAL
            attacked_player.emit(12.0)
    if not is_on_floor():
        velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta
    else:
        velocity.y = -0.05
    move_and_slide()


func take_damage(amount: float) -> void:
    if health <= 0.0 or amount <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        visible = false
        collision_layer = 0
        velocity = Vector3.ZERO


func restore_health(value: float) -> void:
    health = clampf(value, 0.0, max_health)
    visible = health > 0.0
    collision_layer = 1 if health > 0.0 else 0
    attack_timer = 0.0
