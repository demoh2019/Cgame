extends CharacterBody3D
## Original infected enemy for the Days After survival sandbox.
## Physics-raycast local steering around nearby cover. This is not a full
## navmesh planner; long corridors and dead ends need navigation later.

signal eliminated

const MOVE_SPEED := 2.4
const GRAVITY := 18.0
const AGGRO_RADIUS := 19.0
const STRIKE_RADIUS := 1.6
const OBSTACLE_LOOKAHEAD := 2.65
const SIDE_PROBE_DISTANCE := 2.65
const AVOID_RELEASE_SECONDS := 0.55

var target: Node3D
var health: float = 72.0
var strike_cooldown: float = 0.0
var defeated: bool = false
var _avoidance_sign: float = 0.0
var _avoidance_release: float = 0.0


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
        if distance <= AGGRO_RADIUS and distance > 0.01:
            if distance <= STRIKE_RADIUS and _has_attack_line_of_sight():
                if strike_cooldown <= 0.0:
                    target.call("take_damage", 10.0)
                    strike_cooldown = 1.3
            else:
                movement = _steer_around_obstacle(to_target / distance, delta)

    velocity.x = movement.x * MOVE_SPEED
    velocity.z = movement.z * MOVE_SPEED
    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()


func _ray_clearance(direction: Vector3, length: float) -> float:
    # World props use layer 1. Exclude our own RID and ignore the target;
    # seeing the player is not an obstacle to reaching them.
    var origin := global_position + Vector3.UP * 0.3
    var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * length)
    query.collision_mask = 1
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty() or hit.get("collider") == target:
        return length
    return origin.distance_to(hit["position"])


func _has_attack_line_of_sight() -> bool:
    if not is_instance_valid(target):
        return false
    var to_target: Vector3 = target.global_position + Vector3.UP * 0.3
    var origin: Vector3 = global_position + Vector3.UP * 0.3
    var query := PhysicsRayQueryParameters3D.create(origin, to_target)
    query.collision_mask = 1
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    return hit.is_empty() or hit.get("collider") == target


func _steer_around_obstacle(desired: Vector3, delta: float) -> Vector3:
    # Keep a chosen side until the path clears, avoiding left-right jitter.
    # This is inexpensive local avoidance, not pathfinding through a maze.
    var front_clearance := _ray_clearance(desired, OBSTACLE_LOOKAHEAD)
    var blocked := front_clearance < OBSTACLE_LOOKAHEAD - 0.02
    if blocked:
        _avoidance_release = AVOID_RELEASE_SECONDS
        if is_zero_approx(_avoidance_sign):
            var sideways := Vector3(-desired.z, 0.0, desired.x)
            var right := (sideways + desired * 0.25).normalized()
            var left := (-sideways + desired * 0.25).normalized()
            var right_clearance := _ray_clearance(right, SIDE_PROBE_DISTANCE)
            var left_clearance := _ray_clearance(left, SIDE_PROBE_DISTANCE)
            _avoidance_sign = 1.0 if right_clearance >= left_clearance else -1.0
    elif _avoidance_release > 0.0:
        _avoidance_release = maxf(0.0, _avoidance_release - delta)
    else:
        _avoidance_sign = 0.0
        return desired

    var tangent := Vector3(-desired.z, 0.0, desired.x) * _avoidance_sign
    var steering := (tangent + desired * 0.25).normalized()
    # A newly blocked tangent means a corner: prefer the opposite side.
    if blocked and _ray_clearance(steering, 0.85) < 0.5:
        _avoidance_sign *= -1.0
        tangent = Vector3(-desired.z, 0.0, desired.x) * _avoidance_sign
        steering = (tangent + desired * 0.25).normalized()
    return steering


func take_damage(amount: float) -> void:
    if defeated or amount <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        defeated = true
        eliminated.emit()
        queue_free()
