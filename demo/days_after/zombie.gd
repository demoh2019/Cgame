extends CharacterBody3D
## Original infected enemy for the Days After survival sandbox.
## Navigation around obstacles is a future milestone; physical collisions are active.

signal eliminated

const MOVE_SPEED := 2.4
const GRAVITY := 18.0
const AGGRO_RADIUS := 19.0
const STRIKE_RADIUS := 1.6

var target: Node3D
var health: float = 72.0
var strike_cooldown: float = 0.0
var defeated: bool = false


func _ready() -> void:
    collision_layer = 4
    collision_mask = 1
    add_to_group("infected")

    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.39
    capsule.height = 1.8
    collider.shape = capsule
    add_child(collider)

    var body := MeshInstance3D.new()
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.39
    mesh.height = 1.8
    body.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#69815d")
    material.roughness = 0.92
    body.material_override = material
    add_child(body)


func _physics_process(delta: float) -> void:
    if defeated:
        return
    strike_cooldown = maxf(0.0, strike_cooldown - delta)
    var movement := Vector3.ZERO
    if is_instance_valid(target) and float(target.get("health")) > 0.0:
        var to_target: Vector3 = target.global_position - global_position
        to_target.y = 0.0
        var distance: float = to_target.length()
        if distance <= AGGRO_RADIUS and distance > STRIKE_RADIUS:
            movement = to_target.normalized()
        elif distance <= STRIKE_RADIUS and strike_cooldown <= 0.0:
            target.call("take_damage", 10.0)
            strike_cooldown = 1.3

    velocity.x = movement.x * MOVE_SPEED
    velocity.z = movement.z * MOVE_SPEED
    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()

    # Infected can physically wear down player-built defenses that block
    # their route; they do not damage arbitrary static world geometry.
    if movement.length_squared() > 0.0 and strike_cooldown <= 0.0:
        for index in range(get_slide_collision_count()):
            var obstacle: Node3D = get_slide_collision(index).get_collider() as Node3D
            if obstacle != null and obstacle.is_in_group("player_barricades"):
                obstacle.call("take_damage", 18.0)
                strike_cooldown = 1.3
                break


func take_damage(amount: float) -> void:
    if defeated or amount <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        defeated = true
        eliminated.emit()
        queue_free()
