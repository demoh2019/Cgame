extends CharacterBody3D
## Basic melee enemy, intentionally using built-in CharacterBody3D physics.

signal died

const MOVE_SPEED := 2.45
const GRAVITY := 24.0

var health := 100.0
var target
var attack_timer := 0.0
var dead := false


func _ready() -> void:
    collision_layer = 4
    collision_mask = 1
    add_to_group("zombies")

    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.42
    capsule.height = 1.8
    var collision := CollisionShape3D.new()
    collision.shape = capsule
    collision.position.y = 0.9
    add_child(collision)

    var body := MeshInstance3D.new()
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.42
    mesh.height = 1.8
    body.mesh = mesh
    body.position.y = 0.9
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.36, 0.53, 0.32)
    body.material_override = material
    add_child(body)


func _physics_process(delta: float) -> void:
    if dead:
        return
    attack_timer = maxf(0.0, attack_timer - delta)
    var direction := Vector3.ZERO
    if is_instance_valid(target) and not target.dead:
        direction = target.global_position - global_position
        direction.y = 0.0
        var distance: float = direction.length()
        if distance > 1.45 and distance < 25.0:
            direction = direction.normalized()
        else:
            direction = Vector3.ZERO
        if distance <= 1.65 and attack_timer <= 0.0:
            target.take_damage(11.0)
            attack_timer = 1.25

    velocity.x = direction.x * MOVE_SPEED
    velocity.z = direction.z * MOVE_SPEED
    if is_on_floor():
        velocity.y = -0.2
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()


func take_damage(amount: float) -> void:
    if dead:
        return
    health -= maxf(0.0, amount)
    if health <= 0.0:
        dead = true
        died.emit()
        queue_free()
