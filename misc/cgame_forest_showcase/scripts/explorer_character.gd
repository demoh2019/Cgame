extends CharacterBody3D
## Collision-based first-person character for the Aurora Forest sample.
## Movement uses the physics timestep; camera yaw/pitch live on separate nodes.
## It remains independent of world streaming, rendering and savegame services.

@export_range(1.0, 15.0, 0.1) var walk_speed: float = 5.2
@export_range(1.0, 20.0, 0.1) var sprint_speed: float = 8.5
@export_range(1.0, 15.0, 0.1) var jump_speed: float = 6.3
@export_range(1.0, 60.0, 0.1) var gravity_strength: float = 24.0
@export_range(1.0, 60.0, 0.1) var acceleration: float = 25.0
@export_range(0.5, 30.0, 0.1) var air_acceleration: float = 7.0

const CAPSULE_RADIUS: float = 0.35
const CAPSULE_HEIGHT: float = 1.90
const CENTER_ABOVE_GROUND: float = CAPSULE_HEIGHT * 0.5
const EYE_FROM_CENTER: float = 0.76

var movement_enabled: bool = true
var streaming_world: WorldPartition3D


func _ready() -> void:
    floor_snap_length = 0.32
    floor_max_angle = deg_to_rad(48.0)
    safe_margin = 0.04
    motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
    collision_layer = 2
    collision_mask = 1

    if get_node_or_null("CapsuleCollision") == null:
        var collision := CollisionShape3D.new()
        collision.name = "CapsuleCollision"
        var capsule := CapsuleShape3D.new()
        capsule.radius = CAPSULE_RADIUS
        capsule.height = CAPSULE_HEIGHT
        collision.shape = capsule
        add_child(collision)


func _physics_process(delta: float) -> void:
    # Async stream initialization and savegame teleports must not let the
    # character fall before the destination HeightMapShape3D is registered.
    if not movement_enabled:
        velocity = Vector3.ZERO
        return

    var direction := Vector3.ZERO
    if movement_enabled:
        var horizontal := 0.0
        var forward := 0.0
        if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
            horizontal -= 1.0
        if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
            horizontal += 1.0
        if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
            forward += 1.0
        if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
            forward -= 1.0
        direction = (global_basis.x * horizontal - global_basis.z * forward)
        direction.y = 0.0
        if direction.length_squared() > 0.0:
            direction = direction.normalized()

    var speed: float = sprint_speed if movement_enabled and Input.is_physical_key_pressed(KEY_SHIFT) else walk_speed
    var response: float = acceleration if is_on_floor() else air_acceleration
    velocity.x = move_toward(velocity.x, direction.x * speed, response * delta)
    velocity.z = move_toward(velocity.z, direction.z * speed, response * delta)

    # An asynchronously loading neighboring cell may be absent for a frame
    # even though its resource was requested. Stop at the seam rather than
    # moving the capsule beyond the loaded collision tiles.
    var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
    if horizontal_motion.length_squared() > 0.000001:
        var edge_offset: Vector3 = horizontal_motion.normalized() * (CAPSULE_RADIUS + 0.04)
        var upcoming: Vector3 = global_position + horizontal_motion + edge_offset
        var sideways: Vector3 = Vector3(-edge_offset.z, 0.0, edge_offset.x)
        # Check the center and both capsule flanks so diagonal crossings
        # cannot overlap an unloaded corner tile.
        if not _position_has_terrain(upcoming) \
                or not _position_has_terrain(upcoming + sideways) \
                or not _position_has_terrain(upcoming - sideways):
            velocity.x = 0.0
            velocity.z = 0.0

    if is_on_floor():
        if movement_enabled and Input.is_physical_key_pressed(KEY_SPACE):
            velocity.y = jump_speed
        elif velocity.y < 0.0:
            velocity.y = -0.1
    else:
        velocity.y -= gravity_strength * delta

    move_and_slide()


func _position_has_terrain(world_position: Vector3) -> bool:
    if streaming_world == null:
        return true
    var local: Vector3 = streaming_world.to_local(world_position)
    var cell: Vector2i = streaming_world.local_position_to_cell(local)
    return streaming_world.is_cell_loaded(cell)


func teleport_to_ground(world_x: float, world_z: float, ground_y: float) -> void:
    # Teleport is reserved for loading saves / spawning; everyday movement is swept.
    global_position = Vector3(world_x, ground_y + CENTER_ABOVE_GROUND + 0.08, world_z)
    velocity = Vector3.ZERO
