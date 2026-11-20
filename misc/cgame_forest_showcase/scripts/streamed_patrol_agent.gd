extends CharacterBody3D
## Small physics-backed NPC that uses real NavigationAgent3D paths.
## An NPC belongs to a streamed forest tile and is freed with that tile.
## It remains inactive until WorldPartition3D confirms NavigationServer
## region iteration synchronization AND its two-tick physics barrier.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const PATROL_SPEED: float = 2.0
const GRAVITY: float = 24.0
const WAYPOINT_RADIUS: float = 1.4

var streaming_world: WorldPartition3D
var owning_cell: Vector2i
var navigator: NavigationAgent3D
var route_index: int = 0
var navigation_active: bool = false
var completed_waypoints: int = 0
var intercell_route_count: int = 0
var avoidance_velocity_updates: int = 0
var _target_initialized: bool = false
var patrol_anchors: Array[Vector2] = [
    Vector2(8.0, 8.0),
    Vector2(24.0, 8.0),
    Vector2(24.0, 24.0),
    Vector2(8.0, 24.0)
]


func _ready() -> void:
    name = "ForestPatrol"
    collision_layer = 4
    collision_mask = 1
    floor_snap_length = 0.4
    motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

    var collider := CollisionShape3D.new()
    collider.name = "PatrolCapsule"
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.34
    capsule.height = 1.8
    collider.shape = capsule
    add_child(collider)

    var visual := MeshInstance3D.new()
    visual.name = "PatrolMarker"
    var marker_mesh := CapsuleMesh.new()
    marker_mesh.radius = 0.34
    marker_mesh.height = 1.8
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.90, 0.73, 0.26)
    material.roughness = 0.45
    marker_mesh.material = material
    visual.mesh = marker_mesh
    add_child(visual)

    navigator = NavigationAgent3D.new()
    navigator.name = "PatrolNavigationAgent"
    navigator.path_desired_distance = 0.7
    navigator.target_desired_distance = WAYPOINT_RADIUS
    navigator.radius = 0.40
    navigator.avoidance_enabled = false
    navigator.avoidance_mask = 1
    navigator.avoidance_layers = 1
    navigator.avoidance_priority = 0.5
    navigator.max_speed = PATROL_SPEED
    navigator.velocity_computed.connect(_on_safe_velocity)
    add_child(navigator)


func _physics_process(_delta: float) -> void:
    navigation_active = streaming_world != null \
        and streaming_world.is_cell_navigation_ready(owning_cell)
    if not navigation_active:
        navigator.avoidance_enabled = false
        velocity = Vector3.ZERO
        return

    if not navigator.avoidance_enabled:
        navigator.avoidance_enabled = true
    if not _target_initialized or navigator.is_navigation_finished():
        _advance_waypoint()

    # The native engine validates the *entire corridor*, not just the
    # destination. When a neighboring streamed region unloads, an NPC must
    # halt rather than blindly move across missing navigation polygons.
    var target: Vector3 = navigator.target_position
    if not streaming_world.is_navigation_route_ready(global_position, target, 16):
        navigator.velocity = Vector3.ZERO
        return

    var waypoint: Vector3 = navigator.get_next_path_position()
    var direction := Vector3(
        waypoint.x - global_position.x, 0.0,
        waypoint.z - global_position.z)
    var desired := Vector3.ZERO
    if direction.length_squared() > 0.04:
        desired = direction.normalized() * PATROL_SPEED
    # NavigationServer avoidance is a local steering layer only: it does
    # not rewrite pathfinding polygons and cannot replace a navmesh bake.
    navigator.velocity = desired


func _on_safe_velocity(safe_velocity: Vector3) -> void:
    if not navigation_active or streaming_world == null \
            or not streaming_world.is_cell_navigation_ready(owning_cell):
        return
    avoidance_velocity_updates += 1
    velocity.x = safe_velocity.x
    velocity.z = safe_velocity.z
    var delta: float = get_physics_process_delta_time()
    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= GRAVITY * delta
    if Vector2(velocity.x, velocity.z).length_squared() > 0.05:
        look_at(global_position + Vector3(velocity.x, 0.0, velocity.z), Vector3.UP)
    move_and_slide()


func _advance_waypoint() -> void:
    if navigator == null:
        return
    var local: Vector2 = patrol_anchors[route_index % patrol_anchors.size()]
    route_index += 1
    completed_waypoints += 1
    _target_initialized = true
    var x: float = float(owning_cell.x * 32) + local.x
    var z: float = float(owning_cell.y * 32) + local.y

    # Occasionally visit the neighboring east tile, but only when the
    # engine confirms a real NavigationServer route entirely inside loaded
    # navigation regions. No extra cell pins or prefetch are leaked.
    if route_index % 5 == 0:
        var neighbor: Vector2i = owning_cell + Vector2i(1, 0)
        if streaming_world.is_cell_navigation_ready(neighbor):
            var next_x: float = float(neighbor.x * 32) + 8.0
            var next_z: float = float(neighbor.y * 32) + 16.0
            var target := Vector3(
                next_x, TerrainHeight.height_at(next_x, next_z), next_z)
            var route: PackedVector3Array = streaming_world.get_streamed_navigation_path(
                global_position, target, true, 1, 16)
            if route.size() >= 2:
                navigator.target_position = target
                intercell_route_count += 1
                return

    navigator.target_position = Vector3(
        x, TerrainHeight.height_at(x, z), z)
