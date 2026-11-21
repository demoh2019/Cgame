extends StaticBody3D
class_name WorldHostileSentry3D
## A compact stationary foe for streamed cells. Owns its own combat component,
## exposes primitive save state and sleeps with AI interest management.

signal state_changed()
signal sentry_defeated()
signal sentry_attacked_player(amount: float)

const Attributes = preload("res://addons/visual_quality/attribute_component.gd")
const Combatant = preload("res://addons/visual_quality/combat_component.gd")
const Visibility = preload("res://addons/visual_quality/combat_visibility.gd")

@export_range(1.0, 7.0, 0.1) var attack_range: float = 2.8
@export_range(1.0, 50.0, 1.0) var attack_damage: float = 9.0
@export_range(0.5, 5.0, 0.1) var attack_interval: float = 1.7
@export_flags_3d_physics var cover_collision_mask: int = 1

var player: Node3D
var player_combatant: WorldCombatant3D
var combatant: WorldCombatant3D
var attributes: WorldAttributes3D
var ai_enabled: bool = true
var _attack_elapsed: float = 0.0
var _visual: MeshInstance3D


func _ready() -> void:
	_build_body()
	attributes = Attributes.new()
	attributes.name = "SentryAttributes"
	add_child(attributes)
	combatant = Combatant.new()
	combatant.name = "SentryCombatant"
	combatant.team_id = WorldCombatant3D.TEAM_HOSTILE
	combatant.armor = 8.0
	combatant.attributes = attributes
	combatant.damage_taken.connect(_on_damage_taken)
	combatant.defeated.connect(_on_defeated)
	combatant.stun_changed.connect(_on_stun_changed)
	add_child(combatant)
	_update_visual()
	set_ai_enabled(ai_enabled)


func _physics_process(delta: float) -> void:
	if not ai_enabled or not is_finite(delta) or delta <= 0.0 or not combatant.is_alive():
		return
	_attack_elapsed = maxf(_attack_elapsed - delta, 0.0)
	if _attack_elapsed > 0.0 or combatant.is_stunned():
		return
	if not is_instance_valid(player) or not is_instance_valid(player_combatant):
		return
	if not player_combatant.is_alive():
		return
	if global_position.distance_squared_to(player.global_position) > attack_range * attack_range:
		return
	# The same physical cover blocks both player hits and hostile attacks.
	if not Visibility.has_clear_path(get_world_3d(), global_position + Vector3.UP * 1.15,
			player.global_position + Vector3.UP * 1.15, self, player, cover_collision_mask):
		return
	var dealt: float = player_combatant.receive_damage(attack_damage,
		WorldCombatant3D.TEAM_HOSTILE)
	if dealt > 0.0:
		_attack_elapsed = attack_interval
		sentry_attacked_player.emit(dealt)


func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	set_physics_process(enabled)
	if is_instance_valid(combatant):
		combatant.set_physics_process(enabled)


func _build_body() -> void:
	name = "HostileForestSentry"
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = "SentryCollider"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	shape_node.shape = capsule
	shape_node.position.y = 0.9
	add_child(shape_node)
	_visual = MeshInstance3D.new()
	_visual.name = "SentryVisual"
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.43
	mesh.height = 1.8
	_visual.mesh = mesh
	_visual.position.y = 0.9
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.roughness = 0.4
	material.emission_enabled = true
	_visual.material_override = material
	add_child(_visual)


func _on_damage_taken(_amount: float, _health_left: float) -> void:
	_update_visual()
	state_changed.emit()


func _on_stun_changed(_stunned: bool) -> void:
	_update_visual()
	state_changed.emit()


func _on_defeated() -> void:
	collision_layer = 0
	collision_mask = 0
	_update_visual()
	state_changed.emit()
	sentry_defeated.emit()


func _update_visual() -> void:
	if not is_instance_valid(_visual) or not is_instance_valid(combatant):
		return
	var material: StandardMaterial3D = _visual.material_override as StandardMaterial3D
	if not combatant.is_alive():
		material.albedo_color = Color(0.16, 0.16, 0.18)
		material.emission = Color.BLACK
	elif combatant.is_stunned():
		material.albedo_color = Color(0.67, 0.34, 0.96)
		material.emission = Color(0.28, 0.08, 0.52)
	else:
		material.albedo_color = Color(0.80, 0.18, 0.17)
		material.emission = Color(0.45, 0.08, 0.06)


func save_sentry_state() -> Dictionary:
	var state: Dictionary = {}
	if is_instance_valid(attributes) and attributes.health < attributes.get_stat("max_health"):
		state["sentry_health"] = attributes.health
	if is_instance_valid(combatant) and combatant.stun_remaining > 0.0:
		state["sentry_stun"] = combatant.stun_remaining
	return state


func load_sentry_state(state: Dictionary) -> void:
	if not is_instance_valid(combatant):
		return
	var health_value: Variant = state.get("sentry_health", 100.0)
	var stun_value: Variant = state.get("sentry_stun", 0.0)
	var hp: float = float(health_value) if typeof(health_value) in [TYPE_INT, TYPE_FLOAT] else 100.0
	var stun: float = float(stun_value) if typeof(stun_value) in [TYPE_INT, TYPE_FLOAT] else 0.0
	combatant.restore_health(hp, stun)
	collision_layer = 1 if combatant.is_alive() else 0
	collision_mask = 1 if combatant.is_alive() else 0
	_update_visual()
