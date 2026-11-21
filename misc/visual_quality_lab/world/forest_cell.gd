extends Node3D
class_name StreamedForestCell3D
## Scene content, independent from WorldStreamer3D; replace with a crafted
## PackedScene, a biome, or a level chunk without changing the streamer.

const Foliage = preload("res://addons/visual_quality/foliage_chunks.gd")
const NavigationTile = preload("res://addons/visual_quality/navigation_tile.gd")
const NPC = preload("res://addons/visual_quality/streamed_patrol_npc.gd")

signal stream_state_changed()
signal resource_awarded(item_id: String, source_uid: String)

@export var world_seed: int = 20261120
@export var local_chunk_size: float = 14.0

var cell_coord: Vector2i = Vector2i.ZERO
var _quality_profile: int = 1
var _foliage: ChunkedFoliage3D
var _navigation_tile: StreamedNavigationTile3D
var _npc: StreamedPatrolNPC3D
var ai_enabled: bool = true
var _rock: StaticBody3D
var beacon_activated: bool = false
var npc_talk_count: int = 0
var _beacon: MeshInstance3D


func configure_stream_cell(coord: Vector2i) -> void:
	cell_coord = coord


func _ready() -> void:
	_foliage = Foliage.new()
	_foliage.name = "GPUForest"
	_foliage.chunks_per_axis = 1
	_foliage.chunk_size = local_chunk_size
	_foliage.trees_per_chunk = 24
	_foliage.world_seed = Foliage.cell_seed(world_seed, cell_coord.x, cell_coord.y)
	_foliage.clear_radius = 12.0 if cell_coord == Vector2i.ZERO else 0.0
	add_child(_foliage)
	_foliage.set_quality(_quality_profile)
	_create_beacon()
	_create_navigation_and_npc()


func set_quality(profile: int) -> void:
	_quality_profile = clampi(profile, 0, 2)
	if is_instance_valid(_foliage):
		_foliage.set_quality(_quality_profile)
	if is_instance_valid(_npc):
		_npc.think_interval_seconds = [0.9, 0.55, 0.35][_quality_profile]


func set_ai_enabled(value: bool) -> void:
	ai_enabled = value
	if is_instance_valid(_npc):
		_npc.set_physics_process(ai_enabled)


func get_active_npc() -> StreamedPatrolNPC3D:
	return _npc


func _create_navigation_and_npc() -> void:
	_navigation_tile = NavigationTile.new()
	_navigation_tile.name = "NavigationTile"
	_navigation_tile.tile_size = local_chunk_size
	if cell_coord != Vector2i.ZERO:
		# Navigation hole and actual physics blocker use the same footprint.
		_navigation_tile.blocked_rectangles = [Rect2(Vector2(-1.1, -1.1), Vector2(2.2, 2.2))]
	add_child(_navigation_tile)
	if cell_coord != Vector2i.ZERO:
		_create_rock_obstacle()
	_npc = NPC.new()
	_npc.name = "PatrolNPC"
	_npc.cell_seed = Foliage.cell_seed(world_seed, cell_coord.x, cell_coord.y)
	_npc.position = Vector3(-2.0, 0.0, 2.0)
	var owner_streamer: WorldStreamer3D = get_parent() as WorldStreamer3D
	if owner_streamer != null:
		_npc.player = owner_streamer.source
	add_child(_npc)
	set_quality(_quality_profile)
	set_ai_enabled(ai_enabled)


func _create_rock_obstacle() -> void:
	_rock = StaticBody3D.new()
	_rock.name = "NavigationRock"
	_rock.position = Vector3(0.0, 1.0, 0.0)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.2, 2.0, 2.2)
	collider.shape = shape
	_rock.add_child(collider)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = shape.size
	visual.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.31, 0.32, 0.35)
	material.roughness = 0.91
	visual.material_override = material
	_rock.add_child(visual)
	add_child(_rock)


func get_stream_cell_coord() -> Vector2i:
	return cell_coord


func _create_beacon() -> void:
	_beacon = MeshInstance3D.new()
	_beacon.name = "PersistentForestBeacon"
	_beacon.position = Vector3(2.0, 1.3, -2.0)
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.10
	mesh.radial_segments = 12
	mesh.rings = 6
	_beacon.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.emission_enabled = true
	material.roughness = 0.3
	_beacon.material_override = material
	add_child(_beacon)
	_update_beacon_visual()


func get_beacon_world_position() -> Vector3:
	if is_instance_valid(_beacon):
		return _beacon.global_position
	return to_global(Vector3(2.0, 1.3, -2.0))


func try_activate_beacon(player_world_position: Vector3, radius: float = 2.8) -> bool:
	if beacon_activated or radius <= 0.0:
		return false
	if player_world_position.distance_squared_to(get_beacon_world_position()) > radius * radius:
		return false
	beacon_activated = true
	_update_beacon_visual()
	resource_awarded.emit("forest_essence", "beacon:%d:%d" % [cell_coord.x, cell_coord.y])
	stream_state_changed.emit()
	return true


func _update_beacon_visual() -> void:
	if not is_instance_valid(_beacon):
		return
	var material: StandardMaterial3D = _beacon.material_override as StandardMaterial3D
	if beacon_activated:
		material.albedo_color = Color(0.27, 1.0, 0.35)
		material.emission = Color(0.10, 0.80, 0.18)
		material.emission_energy_multiplier = 2.5
	else:
		material.albedo_color = Color(0.98, 0.45, 0.12)
		material.emission = Color(0.96, 0.28, 0.06)
		material.emission_energy_multiplier = 1.6


## Store only modified state; empty dict means default/unmodified.
## Generic streamed-cell interaction provider. No remote caller can activate
## a target outside its range: activation revalidates the actor position.
func get_interaction_targets(eye: Vector3, search_radius: float) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not beacon_activated and eye.distance_squared_to(get_beacon_world_position()) <= pow(minf(search_radius, 2.8), 2.0):
		entries.append({"action_id": "beacon", "position": get_beacon_world_position(),
			"label": "Зажечь лесной маяк", "radius": 2.8})
	if is_instance_valid(_npc):
		var npc_eye: Vector3 = _npc.global_position + Vector3.UP * 1.0
		if eye.distance_squared_to(npc_eye) <= pow(minf(search_radius, 2.6), 2.0):
			entries.append({"action_id": "npc", "position": npc_eye,
				"label": "Поговорить со стражем", "radius": 2.6,
				"target_collider": _npc})
	return entries


func activate_interaction(action_id: String, actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var actor_eye: Vector3 = actor.global_position + Vector3.UP * 1.2
	match action_id:
		"beacon":
			return try_activate_beacon(actor_eye, 2.8)
		"npc":
			if not is_instance_valid(_npc):
				return false
			if actor_eye.distance_squared_to(_npc.global_position + Vector3.UP) > 2.6 * 2.6:
				return false
			npc_talk_count = mini(npc_talk_count + 1, 999)
			stream_state_changed.emit()
			return true
	return false


func get_interaction_message(action_id: String) -> String:
	if action_id == "beacon":
		return "Маяк зажжён — это изменение сохранено в мире"
	if action_id == "npc":
		return "Страж леса: патрулирую сектор %d,%d. Встреч: %d" % [
			cell_coord.x, cell_coord.y, npc_talk_count]
	return ""


func save_stream_state() -> Dictionary:
	var state: Dictionary = {}
	if beacon_activated:
		state["activated"] = true
	if npc_talk_count > 0:
		state["npc_talk_count"] = npc_talk_count
	if is_instance_valid(_npc):
		# Unmodified NPCs do not inflate the persistent save.
		var npc_data: Dictionary = _npc.export_npc_state()
		if _npc.position.distance_squared_to(Vector3(-2.0, 0.0, 2.0)) > 0.05 or _npc.patrol_index != 0:
			state.merge(npc_data)
	return state


func load_stream_state(state: Dictionary) -> void:
	beacon_activated = state.get("activated", false) == true
	npc_talk_count = clampi(int(state.get("npc_talk_count", 0)), 0, 999)
	_update_beacon_visual()
	if is_instance_valid(_npc):
		if state.has("npc_position") or state.has("npc_patrol"):
			_npc.import_npc_state(state)
		else:
			_npc.reset_state()
