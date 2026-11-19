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
        var blocker: Node3D = _find_blocking_barricade()
        if blocker != null and distance <= AGGRO_RADIUS:
            var to_barrier: Vector3 = blocker.global_position - global_position
            to_barrier.y = 0.0
            if to_barrier.length() <= 2.0:
                if strike_cooldown <= 0.0:
                    blocker.call("take_damage", 12.0)
                    strike_cooldown = 1.3
            else:
                movement = to_barrier.normalized()
        elif distance <= AGGRO_RADIUS and distance > STRIKE_RADIUS:
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


func take_damage(amount: float) -> void:
    if defeated or amount <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        defeated = true
        eliminated.emit()
        queue_free()


func _find_blocking_barricade() -> Node3D:
    if not is_instance_valid(target):
        return null
    var origin: Vector3 = global_position + Vector3.UP * 0.25
    var destination: Vector3 = target.global_position + Vector3.UP * 0.25
    if origin.distance_squared_to(destination) < 0.01:
        return null
    var query := PhysicsRayQueryParameters3D.create(origin, destination)
    query.collision_mask = 1
    query.exclude = [get_rid()]
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    var collider: Node3D = hit.get("collider") as Node3D
    if collider != null and collider.is_in_group("shelter_barricades"):
        return collider
    return null
