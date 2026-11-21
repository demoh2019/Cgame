extends CharacterBody3D
## Original infected enemy for the Days After survival sandbox.
## Physical collisions, sight-gated attacks and local wall-follow steering.
## Long-distance pathfinding through ruins still needs a baked navigation mesh.

signal eliminated

const COMBAT_SIGHT = preload("res://combat_sight.gd")
const PROBE_DISTANCE := 2.2
const PROBE_HEIGHT := 0.65
const SIDE_STEP_LOCK := 0.65
const MOVE_SPEED := 2.4
const GRAVITY := 18.0
const AGGRO_RADIUS := 19.0
const STRIKE_RADIUS := 1.6

var target: Node3D
var health: float = 72.0
var strike_cooldown: float = 0.0
var defeated: bool = false
var _side_step: Vector3 = Vector3.ZERO
var _side_step_time: float = 0.0


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
        if distance <= AGGRO_RADIUS:
            if distance > STRIKE_RADIUS or not can_strike_target():
                if distance > 0.01:
                    movement = _avoid_obstacles(to_target.normalized(), distance, delta)
            elif strike_cooldown <= 0.0:
                target.call("take_damage", 10.0)
                strike_cooldown = 1.3

    velocity.x = movement.x * MOVE_SPEED
    velocity.z = movement.z * MOVE_SPEED
    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()


func can_strike_target() -> bool:
    if not is_instance_valid(target) or float(target.get("health")) <= 0.0:
        return false
    var target_body := target as CollisionObject3D
    if target_body == null:
        return false
    # A wall prevents attacks even if horizontal distance is under 1.6 meters.
    return COMBAT_SIGHT.clear(
        get_world_3d().direct_space_state,
        global_position + Vector3.UP * PROBE_HEIGHT,
        target.global_position + Vector3.UP * PROBE_HEIGHT,
        self, target_body
    )


func _avoid_obstacles(desired: Vector3, target_distance: float,
        delta: float) -> Vector3:
    var from: Vector3 = global_position + Vector3.UP * PROBE_HEIGHT
    var hit: Dictionary = COMBAT_SIGHT.first_blocker(
        get_world_3d().direct_space_state, from,
        from + desired * minf(PROBE_DISTANCE, target_distance),
        self, target as CollisionObject3D
    )
    if hit.is_empty():
        _side_step_time = 0.0
        return desired

    var normal: Vector3 = hit.get("normal", Vector3.ZERO)
    normal.y = 0.0
    if normal.length_squared() < 0.01:
        return desired
    normal = normal.normalized()
    _side_step_time = maxf(0.0, _side_step_time - delta)
    if _side_step_time <= 0.0:
        var tangent := Vector3(-normal.z, 0.0, normal.x)
        # Prefer a side whose immediate probe does not hit an obstacle.
        var left_blocked: bool = not COMBAT_SIGHT.clear(
            get_world_3d().direct_space_state, from,
            from + tangent * PROBE_DISTANCE, self
        )
        var right_blocked: bool = not COMBAT_SIGHT.clear(
            get_world_3d().direct_space_state, from,
            from - tangent * PROBE_DISTANCE, self
        )
        if left_blocked and not right_blocked:
            tangent = -tangent
        elif left_blocked == right_blocked and tangent.dot(desired) < 0.0:
            tangent = -tangent
        _side_step = tangent
        _side_step_time = SIDE_STEP_LOCK

    # Gentle outward bias to avoid pressing directly into the wall.
    return (_side_step + normal * 0.2).normalized()


func take_damage(amount: float) -> void:
    if defeated or amount <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        defeated = true
        eliminated.emit()
        queue_free()
