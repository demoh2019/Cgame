extends CharacterBody3D

## Lightweight PvE enemy for the first unified survival / sandbox RPG slice.
## This is game AI only; navigation and physics are provided by Cgame.

@export var maximum_health: float = 70.0
@export var detection_distance: float = 10.0
@export var strike_distance: float = 1.65
@export var movement_speed: float = 2.35
@export var strike_damage: float = 7.0
@export var strike_interval: float = 1.5

var health: float = 70.0
var strike_cooldown: float = 0.0
var target: CharacterBody3D


func _ready() -> void:
    health = maximum_health
    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.37
    capsule.height = 1.7
    collision.shape = capsule
    add_child(collision)

    var visual := MeshInstance3D.new()
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.37
    mesh.height = 1.7
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#72866a")
    visual.material_override = material
    add_child(visual)

    target = get_parent().get_node_or_null("Player") as CharacterBody3D


func _physics_process(delta: float) -> void:
    if health <= 0.0:
        return
    strike_cooldown = maxf(0.0, strike_cooldown - delta)
    if not is_on_floor():
        velocity.y -= 18.0 * delta

    velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
    velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
    if is_instance_valid(target) and float(target.get("health")) > 0.0:
        var offset := target.global_position - global_position
        offset.y = 0.0
        var distance := offset.length()
        if distance <= detection_distance:
            if distance > strike_distance:
                var direction := offset.normalized()
                velocity.x = direction.x * movement_speed
                velocity.z = direction.z * movement_speed
                look_at(global_position + direction, Vector3.UP)
            elif strike_cooldown <= 0.0 and target.has_method("receive_damage"):
                target.call("receive_damage", strike_damage)
                strike_cooldown = strike_interval
    move_and_slide()


func receive_hit(amount: float) -> int:
    # 0 = rejected, 1 = wounded, 2 = killed. The player awards loot once.
    if health <= 0.0 or not is_finite(amount) or amount <= 0.0:
        return 0
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        queue_free()
        return 2
    return 1
