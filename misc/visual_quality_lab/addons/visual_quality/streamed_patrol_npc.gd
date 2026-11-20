extends CharacterBody3D
class_name StreamedPatrolNPC3D
## Cell-local patrol / proximity awareness with real NavigationAgent3D paths.
## High-level decisions are throttled; path following runs on physics ticks.
## The cell root saves and restores this NPC's *local* progress on unload.

signal behavior_changed(new_behavior: int)

enum Behavior { PATROL, ALERT }

@export_range(0.5, 8.0, 0.1) var walking_speed: float = 2.0
@export_range(0.5, 8.0, 0.1) var alert_speed: float = 3.5
@export_range(1.0, 12.0, 0.5) var alert_radius: float = 4.5
@export_range(2.0, 18.0, 0.5) var disengage_radius: float = 7.0
@export_range(0.1, 2.0, 0.05) var think_interval_seconds: float = 0.45
@export_range(2.0, 8.0, 0.5) var patrol_extent: float = 4.0

var player: Node3D
var cell_seed: int = 0
var behavior: int = Behavior.PATROL
var patrol_index: int = 0
var navigation_agent: NavigationAgent3D
var _thought_elapsed: float = 0.0
var _navigation_ready: bool = false
var _original_local_position: Vector3
var _visual: MeshInstance3D


func _ready() -> void:
	_original_local_position = position
	_build_character()
	# The navigation map is not synchronized until a physics tick has elapsed.
	_navigation_ready = false
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if not _navigation_ready:
		if NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0:
			return
		_navigation_ready = true
		_set_patrol_target()
	_thought_elapsed += delta
	if _thought_elapsed >= think_interval_seconds:
		_thought_elapsed = 0.0
		_update_behavior()
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	var flat_delta: Vector3 = next_position - global_position
	flat_delta.y = 0.0
	var horizontal: Vector3 = flat_delta.normalized() * (alert_speed if behavior == Behavior.ALERT else walking_speed)
	velocity = Vector3(horizontal.x, 0.0, horizontal.z)
	move_and_slide()


func _update_behavior() -> void:
	var distance_sq: float = INF
	if player != null and is_instance_valid(player):
		distance_sq = player.global_position.distance_squared_to(global_position)
	var should_be_alert: bool = should_alert(behavior == Behavior.ALERT,
		distance_sq, alert_radius, disengage_radius)
	if should_be_alert:
		if behavior != Behavior.ALERT:
			behavior = Behavior.ALERT
			behavior_changed.emit(behavior)
			_update_visual()
		# Avoid resetting the navigation target on every physics tick.
		var origin: Vector3 = get_parent_node_3d().global_position
		var relative: Vector3 = player.global_position - origin
		var target: Vector3 = origin + Vector3(
			clampf(relative.x, -patrol_extent, patrol_extent), 0.0,
			clampf(relative.z, -patrol_extent, patrol_extent)
		)
		if navigation_agent.target_position.distance_squared_to(target) > 0.5:
			navigation_agent.target_position = target
	else:
		if behavior != Behavior.PATROL:
			behavior = Behavior.PATROL
			behavior_changed.emit(behavior)
			_update_visual()
			_set_patrol_target()
		elif navigation_agent.is_navigation_finished():
			patrol_index = (patrol_index + 1) % 4
			_set_patrol_target()


func _set_patrol_target() -> void:
	if not _navigation_ready or navigation_agent == null:
		return
	var origin: Vector3 = get_parent_node_3d().global_position
	navigation_agent.target_position = origin + patrol_point(patrol_index, patrol_extent, cell_seed)


func _build_character() -> void:
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "NPCBodyCollider"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.35
	collider.shape = capsule
	collider.position.y = 0.72
	add_child(collider)
	_visual = MeshInstance3D.new()
	_visual.name = "NPCVisual"
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.29
	mesh.height = 1.4
	_visual.mesh = mesh
	_visual.position.y = 0.75
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.roughness = 0.55
	_visual.material_override = material
	add_child(_visual)
	_update_visual()
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "PatrolNavigationAgent"
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.65
	# RVO callbacks have an appreciable cost with many agents: opt-in only.
	navigation_agent.avoidance_enabled = false
	add_child(navigation_agent)


func _update_visual() -> void:
	if _visual == null:
		return
	var material: StandardMaterial3D = _visual.material_override as StandardMaterial3D
	material.albedo_color = Color(1.0, 0.40, 0.23) if behavior == Behavior.ALERT else Color(0.24, 0.48, 0.90)


func export_npc_state() -> Dictionary:
	# Do not serialize transient player/NavigationAgent references.
	return {"npc_position": position, "npc_patrol": patrol_index}


func import_npc_state(value: Dictionary) -> void:
	if typeof(value.get("npc_position")) == TYPE_VECTOR3:
		var p: Vector3 = value["npc_position"]
		if is_finite(p.x) and is_finite(p.z):
			position = Vector3(clampf(p.x, -patrol_extent, patrol_extent), 0.0,
				clampf(p.z, -patrol_extent, patrol_extent))
	patrol_index = clampi(int(value.get("npc_patrol", 0)), 0, 3)
	behavior = Behavior.PATROL
	_update_visual()
	_set_patrol_target()


func reset_state() -> void:
	position = _original_local_position
	patrol_index = 0
	behavior = Behavior.PATROL
	_update_visual()
	_set_patrol_target()


static func patrol_point(index: int, extent: float, seed: int) -> Vector3:
	var e: float = maxf(extent, 0.0)
	var corner: int = posmod(index + posmod(seed, 4), 4)
	match corner:
		0:
			return Vector3(-e, 0.0, -e)
		1:
			return Vector3(e, 0.0, -e)
		2:
			return Vector3(e, 0.0, e)
		_:
			return Vector3(-e, 0.0, e)


static func should_alert(is_currently_alert: bool, distance_sq: float,
		enter_radius: float, exit_radius: float) -> bool:
	var radius: float = maxf(exit_radius if is_currently_alert else enter_radius, 0.0)
	return is_finite(distance_sq) and distance_sq <= radius * radius
