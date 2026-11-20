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
    add_child(navigator)


func _physics_process(delta: float) -> void:
    navigation_active = streaming_world != null \
        and streaming_world.is_cell_navigation_ready(owning_cell)
    if not navigation_active:
        velocity = Vector3.ZERO
        return

    if navigator.is_navigation_finished():
        _advance_waypoint()

    var waypoint: Vector3 = navigator.get_next_path_position()
    var direction := Vector3(
        waypoint.x - global_position.x, 0.0,
        waypoint.z - global_position.z)
    if direction.length_squared() > 0.04:
        direction = direction.normalized()
        velocity.x = direction.x * PATROL_SPEED
        velocity.z = direction.z * PATROL_SPEED
        look_at(global_position + direction, Vector3.UP)
    else:
        velocity.x = 0.0
        velocity.z = 0.0

    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()


func _advance_waypoint() -> void:
    if navigator == null:
        return
    var anchor: Vector2 = patrol_anchors[route_index % patrol_anchors.size()]
    route_index += 1
    completed_waypoints += 1
    # Stay within the owning tile. Navigation may connect to neighboring
    # regions, but this prototype does not keep adjacent regions resident.
    var local_x: float = float(owning_cell.x * 32) + anchor.x
    var local_z: float = float(owning_cell.y * 32) + anchor.y
    navigator.target_position = Vector3(
        local_x, TerrainHeight.height_at(local_x, local_z), local_z)
