extends CharacterBody3D
## Lightweight close-range forest enemy.
## The owning encounter director decides when physics is active; inactive
## stalkers don't run per-frame AI (similar to an AI significance tier).

signal attack_landed(amount: int)
signal defeated(encounter_id: String)

const MAX_HEALTH: int = 3
const ATTACK_DAMAGE: int = 16
const ATTACK_DISTANCE: float = 1.75
const ATTACK_COOLDOWN: float = 1.6
const AGGRO_DISTANCE: float = 14.0
const LEASH_DISTANCE: float = 22.0
const WALK_SPEED: float = 2.8
const NAVIGATION_PRIORITY: int = 2
const AVOIDANCE_CHECK_DISTANCE: float = 2.7
const AVOIDANCE_ANGLE: float = 0.75
const AVOIDANCE_EYE_HEIGHT: float = 0.45
const NAVMESH_REQUERY_FRAMES: int = 12

var encounter_id: String = ""
var target: Node3D
var streamer: WorldPartition3D
var steering_direction: Vector3 = Vector3.ZERO
var steering_updates: int = 0 # Diagnostics: actual CPU steering recalculations.
var avoidance_turns: int = 0 # Number of recalculations that saw a blocking collider.
var navmesh_path_queries: int = 0
var navmesh_path_successes: int = 0
var last_navmesh_query_frame: int = -10000
var navmesh_waypoint: Vector3 = Vector3.ZERO
var navmesh_goal: Vector3 = Vector3.ZERO
var navmesh_path_valid: bool = false
var home_position: Vector3
var health: int = MAX_HEALTH
var active: bool = false
var attack_timer: float = 0.0


func _ready() -> void:
    collision_layer = 4
    collision_mask = 1 # Terrain/obstacles only, not the player.
    floor_snap_length = 0.25
    floor_max_angle = deg_to_rad(45.0)

    var collision := CollisionShape3D.new()
    collision.name = "StalkerCapsule"
    var shape := CapsuleShape3D.new()
    shape.radius = 0.42
    shape.height = 1.65
    collision.shape = shape
    add_child(collision)

    var body := MeshInstance3D.new()
    body.name = "StalkerBody"
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.41
    mesh.height = 1.60
    mesh.radial_segments = 8
    mesh.rings = 5
    var hide := StandardMaterial3D.new()
    hide.albedo_color = Color(0.10, 0.21, 0.20)
    hide.metallic = 0.10
    hide.roughness = 0.72
    mesh.material = hide
    body.mesh = mesh
    add_child(body)

    var eye_mesh := SphereMesh.new()
    eye_mesh.radius = 0.12
    eye_mesh.height = 0.24
    eye_mesh.radial_segments = 7
    eye_mesh.rings = 4
    var eye_mat := StandardMaterial3D.new()
    eye_mat.albedo_color = Color(1.0, 0.30, 0.14)
    eye_mat.emission_enabled = true
    eye_mat.emission = Color(1.0, 0.18, 0.07)
    eye_mat.emission_energy_multiplier = 3.0
    eye_mesh.material = eye_mat
    for offset in [-0.18, 0.18]:
        var eye := MeshInstance3D.new()
        eye.name = "Eye"
        eye.mesh = eye_mesh
        eye.position = Vector3(offset, 0.27, -0.34)
        add_child(eye)

    set_encounter_active(false)


func configure(id: String, player: Node3D, spawn_position: Vector3,
        partition: WorldPartition3D = null) -> void:
    encounter_id = id
    target = player
    home_position = spawn_position
    global_position = spawn_position
    streamer = partition
    if is_instance_valid(streamer):
        streamer.register_navigation_agent(encounter_id, self, NAVIGATION_PRIORITY)


func _exit_tree() -> void:
    if is_instance_valid(streamer) and not encounter_id.is_empty():
        streamer.unregister_navigation_agent_if_owner(encounter_id, self)


func _steering_ray_blocked(from: Vector3, direction: Vector3) -> bool:
    var query := PhysicsRayQueryParameters3D.create(
        from, from + direction * AVOIDANCE_CHECK_DISTANCE)
    query.collision_mask = 1 # Terrain and tree/rock collision only.
    query.exclude = [get_rid()]
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    return not hit.is_empty() and hit.get("collider") != target


func _navmesh_direction(goal: Vector3, fallback: Vector3) -> Vector3:
    # NavigationServer queries are issued only after a native physics-frame
    # steering grant and at most once per NPC per 12 physics ticks.
    if not is_instance_valid(streamer):
        return fallback
    var from_cell: Vector2i = streamer.local_position_to_cell(
        streamer.to_local(global_position))
    var to_cell: Vector2i = streamer.local_position_to_cell(
        streamer.to_local(goal))
    if (not streamer.is_cell_navigation_ready(from_cell)
            or not streamer.is_cell_navigation_ready(to_cell)):
        navmesh_path_valid = false
        return fallback
    var frame: int = Engine.get_physics_frames()
    if (frame - last_navmesh_query_frame >= NAVMESH_REQUERY_FRAMES
            or goal.distance_squared_to(navmesh_goal) > 16.0):
        last_navmesh_query_frame = frame
        navmesh_goal = goal
        navmesh_path_valid = false
        navmesh_path_queries += 1
        var route: PackedVector3Array = NavigationServer3D.map_get_path(
            get_world_3d().navigation_map, global_position, goal, true, 1)
        if route.size() >= 2 and route[route.size() - 1].distance_to(goal) <= 4.0:
            for waypoint in route:
                var to_waypoint: Vector3 = waypoint - global_position
                to_waypoint.y = 0.0
                if to_waypoint.length_squared() > 0.7:
                    navmesh_waypoint = waypoint
                    navmesh_path_valid = true
                    navmesh_path_successes += 1
                    break
    if navmesh_path_valid:
        var towards: Vector3 = navmesh_waypoint - global_position
        towards.y = 0.0
        if towards.length_squared() > 0.2:
            return towards.normalized()
    return fallback


func _recompute_steering(desired_direction: Vector3, goal: Vector3) -> Vector3:
    steering_updates += 1
    var direction: Vector3 = _navmesh_direction(goal, desired_direction).normalized()
    if direction == Vector3.ZERO:
        return direction
    var origin: Vector3 = global_position + Vector3.UP * AVOIDANCE_EYE_HEIGHT
    if not _steering_ray_blocked(origin, direction):
        return direction
    avoidance_turns += 1
    # Local obstacle avoidance without requiring a baked navigation mesh.
    # Keep this bounded to three PhysicsServer queries per granted update.
    var left: Vector3 = direction.rotated(Vector3.UP, AVOIDANCE_ANGLE)
    var right: Vector3 = direction.rotated(Vector3.UP, -AVOIDANCE_ANGLE)
    var left_blocked: bool = _steering_ray_blocked(origin, left)
    var right_blocked: bool = _steering_ray_blocked(origin, right)
    if not left_blocked and right_blocked:
        return left
    if not right_blocked and left_blocked:
        return right
    if not left_blocked and not right_blocked:
        return left if steering_direction.dot(left) >= steering_direction.dot(right) else right
    # Both side probes blocked: avoid oscillating direction every tick.
    return left if steering_direction.dot(left) >= steering_direction.dot(right) else right


func set_encounter_active(enabled: bool) -> void:
    active = enabled and health > 0
    visible = active
    set_physics_process(active)
    if not active:
        velocity = Vector3.ZERO
        steering_direction = Vector3.ZERO


func is_alive() -> bool:
    return health > 0


func get_health() -> int:
    return health


func take_damage(amount: int) -> bool:
    if health <= 0 or amount <= 0:
        return false
    health = maxi(health - amount, 0)
    if health == 0:
        set_encounter_active(false)
        defeated.emit(encounter_id)
        queue_free()
    return true


func _physics_process(delta: float) -> void:
    if not active or not is_instance_valid(target) or delta <= 0.0:
        return

    attack_timer = maxf(0.0, attack_timer - delta)
    var player_vector: Vector3 = target.global_position - global_position
    player_vector.y = 0.0
    var player_distance: float = player_vector.length()
    var away_from_home: Vector3 = home_position - global_position
    away_from_home.y = 0.0

    var walk_direction := Vector3.ZERO
    var movement_goal: Vector3 = target.global_position
    if away_from_home.length() > LEASH_DISTANCE:
        walk_direction = away_from_home.normalized()
        movement_goal = home_position
    elif player_distance < AGGRO_DISTANCE and player_distance > ATTACK_DISTANCE * 0.9:
        walk_direction = player_vector.normalized()
    elif player_distance >= AGGRO_DISTANCE and away_from_home.length() > 1.5:
        walk_direction = away_from_home.normalized()
        movement_goal = home_position

    # Moving enemies receive a higher scheduling tier than stationary
    # combatants; idle actors do not waste the first priority slots.
    if is_instance_valid(streamer):
        streamer.set_navigation_agent_priority(encounter_id,
            NAVIGATION_PRIORITY if walk_direction.length_squared() >= 0.001 else 0)

    # The native scheduler bounds expensive obstacle probes/path recomputation
    # across all active NPCs; each agent reuses its previous local steering
    # between granted physics frames. No navmesh is assumed in this demo.
    if walk_direction.length_squared() < 0.001:
        steering_direction = Vector3.ZERO
    elif not is_instance_valid(streamer):
        steering_direction = _recompute_steering(walk_direction, movement_goal)
    elif streamer.try_acquire_navigation_update(encounter_id):
        steering_direction = _recompute_steering(walk_direction, movement_goal)

    velocity.x = move_toward(velocity.x, steering_direction.x * WALK_SPEED, delta * 14.0)
    velocity.z = move_toward(velocity.z, steering_direction.z * WALK_SPEED, delta * 14.0)
    velocity.y -= 24.0 * delta
    move_and_slide()

    if player_distance < ATTACK_DISTANCE and attack_timer <= 0.0:
        attack_timer = ATTACK_COOLDOWN
        attack_landed.emit(ATTACK_DAMAGE)
