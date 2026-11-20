extends CharacterBody3D

# A small real NavigationAgent3D user that holds the cells along its patrol.
# Route leases are owned by this character, never serialized as save-game IDs.
const CELL_FROM := Vector2i(0, 0)
const CELL_TO := Vector2i(1, 0)
const WAYPOINTS := [
    Vector3(110.0, 0.1, 64.0),
    Vector3(146.0, 0.1, 64.0),
]
const WALK_SPEED := 7.0
const ARRIVAL_DISTANCE := 1.8

var streamer: Node3D
var navigation_agent: NavigationAgent3D
var route_tokens: Array = []
var patrol_enabled := true
var target_index := 1
var completed_crossings := 0
var navigation_sync_frames := 3
var route_status := "Awaiting streamed corridor"

func configure(p_streamer: Node3D) -> void:
    streamer = p_streamer

func _ready() -> void:
    name = "RoutePatrolAgent"
    var visual := MeshInstance3D.new()
    visual.name = "PatrolMarker"
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.45
    capsule.height = 1.8
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.18, 0.65, 1.0)
    material.emission_enabled = true
    material.emission = Color(0.04, 0.2, 0.4)
    material.emission_energy_multiplier = 0.7
    capsule.material = material
    visual.mesh = capsule
    visual.position.y = 0.95
    add_child(visual)

    var collider := CollisionShape3D.new()
    collider.name = "AgentCollider"
    var shape := CapsuleShape3D.new()
    shape.radius = 0.45
    shape.height = 1.8
    collider.shape = shape
    collider.position.y = 0.95
    add_child(collider)

    navigation_agent = NavigationAgent3D.new()
    navigation_agent.name = "PathFollower"
    navigation_agent.path_desired_distance = 1.25
    navigation_agent.target_desired_distance = ARRIVAL_DISTANCE
    navigation_agent.navigation_layers = 1
    add_child(navigation_agent)

    if global_position == Vector3.ZERO:
        global_position = WAYPOINTS[0]
    _reserve_route()

func _reserve_route() -> void:
    if streamer == null or not is_instance_valid(streamer) or not patrol_enabled:
        return
    if not route_tokens.is_empty():
        return
    route_tokens = streamer.call("acquire_cell_route", CELL_FROM, CELL_TO)
    if route_tokens.size() != 2:
        route_status = "Route blocked or token capacity reached"
        route_tokens.clear()
        return
    navigation_sync_frames = 3
    route_status = "Waiting for cell streaming"

func _release_route() -> void:
    if not route_tokens.is_empty() and is_instance_valid(streamer):
        streamer.call("release_cell_route", route_tokens)
    route_tokens.clear()

func _exit_tree() -> void:
    _release_route()

func set_patrol_enabled(p_enabled: bool) -> void:
    if patrol_enabled == p_enabled:
        return
    patrol_enabled = p_enabled
    velocity = Vector3.ZERO
    if patrol_enabled:
        _reserve_route()
    else:
        _release_route()
        route_status = "Patrol paused"

func _physics_process(_delta: float) -> void:
    if not patrol_enabled:
        return
    if route_tokens.is_empty():
        _reserve_route()
        return
    if not is_instance_valid(streamer):
        return
    if not bool(streamer.call("is_cell_loaded", CELL_FROM)) or not bool(streamer.call("is_cell_loaded", CELL_TO)):
        route_status = "Waiting for both navigation cells"
        velocity = Vector3.ZERO
        return

    if navigation_sync_frames > 0:
        navigation_sync_frames -= 1
        if navigation_sync_frames == 0:
            navigation_agent.target_position = WAYPOINTS[target_index]
        return

    var destination: Vector3 = WAYPOINTS[target_index]
    if global_position.distance_to(destination) < ARRIVAL_DISTANCE:
        target_index = 1 - target_index
        completed_crossings += 1
        destination = WAYPOINTS[target_index]
        navigation_agent.target_position = destination

    if navigation_agent.is_navigation_finished():
        route_status = "Waiting for a connected path"
        velocity = Vector3.ZERO
        return

    # Must call exactly once each physics frame while following the path.
    var next_position := navigation_agent.get_next_path_position()
    var delta_to_next := next_position - global_position
    delta_to_next.y = 0.0
    if delta_to_next.length() < 0.05:
        velocity = Vector3.ZERO
        return

    var direction := delta_to_next.normalized()
    velocity = Vector3(direction.x * WALK_SPEED, 0.0, direction.z * WALK_SPEED)
    move_and_slide()
    route_status = "Patrolling across cell edge"

func capture_patrol_state() -> Dictionary:
    return {
        "position": global_position,
        "target_index": target_index,
        "completed_crossings": completed_crossings,
        "enabled": patrol_enabled,
    }

func restore_patrol_state(state: Dictionary) -> void:
    var saved_position: Variant = state.get("position")
    if saved_position is Vector3 and (saved_position as Vector3).is_finite():
        # Keep corrupt save data inside the intended two-cell demonstration.
        var point: Vector3 = saved_position
        global_position = Vector3(clampf(point.x, 8.0, 246.0), 0.1, clampf(point.z, 8.0, 120.0))
    target_index = clampi(int(state.get("target_index", 1)), 0, 1)
    completed_crossings = clampi(int(state.get("completed_crossings", 0)), 0, 1000000000)
    set_patrol_enabled(bool(state.get("enabled", true)))
    navigation_sync_frames = 3
    if navigation_agent != null:
        navigation_agent.target_position = WAYPOINTS[target_index]

func get_patrol_status() -> Dictionary:
    return {
        "enabled": patrol_enabled,
        "route_tokens": route_tokens.size(),
        "crossings": completed_crossings,
        "status": route_status,
        "current_cell": Vector2i(floori(global_position.x / 128.0), floori(global_position.z / 128.0)),
    }
