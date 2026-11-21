extends Node3D
class_name ExplorationQuest3D
## Playable vertical slice: deterministic light-shard hunt and local save/load.
## Independent of engine internals, networking, and commercial game economy.

signal progress_changed(collected: int, total: int)
signal pickup_hint_changed(message: String)
signal quest_finished()
signal shard_collected(index: int)

@export_range(1, 32, 1) var shard_count: int = 12
@export_range(4.0, 40.0, 1.0) var spawn_min_radius: float = 15.0
@export_range(10.0, 50.0, 1.0) var spawn_max_radius: float = 35.0
@export_range(1.0, 5.0, 0.1) var pickup_distance: float = 2.5
@export var world_seed: int = 20261120
@export var save_enabled: bool = true
@export var save_path: String = "user://visual_quality_quest_v1.cfg"

var player: Node3D
var positions: PackedVector3Array = PackedVector3Array()
var collected_ids: PackedInt32Array = PackedInt32Array()
var _shards: Array[MeshInstance3D] = []
var _hint_elapsed: float = 0.0
var _last_hint: String = ""
var _finished_emitted: bool = false


func _ready() -> void:
	positions = generate_positions(world_seed, shard_count, spawn_min_radius, spawn_max_radius)
	load_progress()
	_build_shards()
	progress_changed.emit(collected_ids.size(), positions.size())
	_update_hint()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_hint_elapsed += delta
	if _hint_elapsed >= 0.20:
		_hint_elapsed = 0.0
		_update_hint()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		try_collect_nearest()
		get_viewport().set_input_as_handled()


func _build_shards() -> void:
	_shards.clear()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.44
	mesh.height = 0.88
	mesh.radial_segments = 16
	mesh.rings = 8
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.90, 0.97)
	material.emission_enabled = true
	material.emission = Color(0.10, 0.72, 1.0)
	material.emission_energy_multiplier = 2.0
	material.metallic = 0.12
	material.roughness = 0.22
	mesh.material = material
	for i in range(positions.size()):
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "LightShard_%02d" % i
		node.mesh = mesh
		node.position = positions[i]
		node.visible = not collected_ids.has(i)
		add_child(node)
		_shards.append(node)


func try_collect_nearest() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var index: int = nearest_pickup_id(to_local(player.global_position),
		positions, collected_ids, pickup_distance)
	if index == -1:
		return false
	return collect_shard(index)


func collect_shard(index: int) -> bool:
	if index < 0 or index >= positions.size() or collected_ids.has(index):
		return false
	collected_ids.append(index)
	if index < _shards.size():
		_shards[index].visible = false
	save_progress()
	shard_collected.emit(index)
	progress_changed.emit(collected_ids.size(), positions.size())
	_update_hint()
	if collected_ids.size() == positions.size() and not _finished_emitted:
		_finished_emitted = true
		quest_finished.emit()
	return true


## WorldInteractionRouter3D provider protocol. The legacy F pickup remains.
func get_interaction_targets(eye: Vector3, search_radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var radius_sq: float = pow(minf(search_radius, pickup_distance), 2.0)
	for index in range(positions.size()):
		if collected_ids.has(index):
			continue
		var global_pos: Vector3 = to_global(positions[index])
		if eye.distance_squared_to(global_pos) <= radius_sq:
			result.append({"action_id": "shard_%d" % index, "position": global_pos,
				"label": "Собрать световой осколок", "radius": pickup_distance})
	return result


func activate_interaction(action_id: String, actor: Node3D) -> bool:
	if not action_id.begins_with("shard_") or not is_instance_valid(actor):
		return false
	var number: String = action_id.substr(6)
	if not number.is_valid_int():
		return false
	var index: int = int(number)
	if index < 0 or index >= positions.size() or collected_ids.has(index):
		return false
	var eye: Vector3 = actor.global_position + Vector3.UP * 1.2
	if eye.distance_squared_to(to_global(positions[index])) > pickup_distance * pickup_distance:
		return false
	return collect_shard(index)


func get_interaction_message(_action_id: String) -> String:
	return "Световой осколок собран"


func reset_quest() -> void:
	collected_ids.clear()
	_finished_emitted = false
	for node in _shards:
		node.visible = true
	save_progress()
	progress_changed.emit(0, positions.size())
	_update_hint()


func collected_count() -> int:
	return collected_ids.size()


func current_hint() -> String:
	return _last_hint


func _update_hint() -> void:
	var result: String
	if collected_ids.size() >= positions.size():
		result = "Quest complete! All light shards recovered. Press R to replay."
	elif player == null or not is_instance_valid(player):
		result = "Explore the forest and find glowing blue shards."
	else:
		var relative: Vector3 = to_local(player.global_position)
		var nearest: int = nearest_pickup_id(relative, positions, collected_ids, 100000.0)
		if nearest < 0:
			result = "No shards remaining."
		else:
			var distance: float = relative.distance_to(positions[nearest])
			if distance <= pickup_distance:
				result = "Press F to collect light shard (%0.1f m)" % distance
			else:
				result = "Nearest light shard: %0.0f m away. Move with WASD. Jump Space; V toggles flight." % distance
	if result != _last_hint:
		_last_hint = result
		pickup_hint_changed.emit(result)


func save_progress() -> void:
	if not save_enabled:
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("quest", "version", 1)
	config.set_value("quest", "seed", world_seed)
	config.set_value("quest", "total", positions.size())
	config.set_value("quest", "collected", collected_ids)
	var error: Error = config.save(save_path)
	if error != OK:
		push_warning("ExplorationQuest3D: failed to save progress (%d)" % error)


func load_progress() -> void:
	collected_ids.clear()
	if not save_enabled:
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path) != OK:
		return
	if config.get_value("quest", "version", -1) != 1:
		return
	if config.get_value("quest", "seed", 0) != world_seed:
		return
	if config.get_value("quest", "total", -1) != positions.size():
		return
	var raw: Variant = config.get_value("quest", "collected", PackedInt32Array())
	if typeof(raw) != TYPE_PACKED_INT32_ARRAY:
		return
	for index in raw:
		if index >= 0 and index < positions.size() and not collected_ids.has(index):
			collected_ids.append(index)
	_finished_emitted = collected_ids.size() == positions.size()


## Pure deterministic helpers; verify them without rendering or a player node.
static func generate_positions(seed: int, count: int, min_radius: float,
		max_radius: float) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if count <= 0 or not is_finite(min_radius) or not is_finite(max_radius):
		return result
	var minimum: float = maxf(min_radius, 0.0)
	var maximum: float = maxf(max_radius, minimum)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var safe_count: int = mini(count, 32)
	for i in range(safe_count):
		var angle: float = (float(i) + rng.randf_range(-0.28, 0.28)) / float(safe_count) * TAU
		var distance: float = rng.randf_range(minimum, maximum)
		result.append(Vector3(cos(angle) * distance, 1.4, sin(angle) * distance))
	return result


static func nearest_pickup_id(player_pos: Vector3, shard_positions: PackedVector3Array,
		claimed: PackedInt32Array, maximum_distance: float) -> int:
	if maximum_distance < 0.0:
		return -1
	var max_distance_squared: float = maximum_distance * maximum_distance
	var closest: int = -1
	for i in range(shard_positions.size()):
		if claimed.has(i):
			continue
		var squared: float = player_pos.distance_squared_to(shard_positions[i])
		if squared <= max_distance_squared:
			closest = i
			max_distance_squared = squared
	return closest
