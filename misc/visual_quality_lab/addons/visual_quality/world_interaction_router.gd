extends Node
class_name WorldInteractionRouter3D
## Centralized interaction selection for streamable game worlds. A provider
## offers get_interaction_targets(origin, radius) and activate_interaction(id,
## actor). Streaming cells are queried spatially; no unloaded scene is retained.

signal focused_action_changed(label: String, stable_id: String)
signal interaction_completed(stable_id: String, success: bool, message: String)

@export_range(0.1, 0.6, 0.05) var focus_refresh_seconds: float = 0.12
@export_range(1.0, 8.0, 0.5) var max_query_distance: float = 3.5
@export_range(-0.5, 1.0, 0.05) var min_view_dot: float = 0.15
@export var require_line_of_sight: bool = false
@export_flags_3d_physics var visibility_collision_mask: int = 1
@export var interaction_enabled: bool = true

var streamer: WorldStreamer3D
var quest: ExplorationQuest3D
var player: Node3D
var camera: Camera3D
var last_candidate_count: int = 0
var last_scanned_cells: int = 0
var _elapsed: float = 0.0
var _focused: Dictionary = {}


func _ready() -> void:
	if is_instance_valid(streamer):
		streamer.cell_about_to_unload.connect(_on_cell_about_to_unload)


func _exit_tree() -> void:
	if is_instance_valid(streamer) and streamer.cell_about_to_unload.is_connected(_on_cell_about_to_unload):
		streamer.cell_about_to_unload.disconnect(_on_cell_about_to_unload)


func _physics_process(delta: float) -> void:
	if not interaction_enabled or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= focus_refresh_seconds:
		_elapsed = 0.0
		refresh_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		try_interact()
		get_viewport().set_input_as_handled()


func refresh_focus() -> Dictionary:
	if not interaction_enabled:
		_set_focus({})
		return {}
	var chosen: Dictionary = find_best_action()
	_set_focus(chosen)
	return chosen.duplicate()


func current_label() -> String:
	return str(_focused.get("label", ""))


func current_id() -> String:
	return str(_focused.get("uid", ""))


func _set_focus(action: Dictionary) -> void:
	var old_id: String = str(_focused.get("uid", ""))
	var old_label: String = str(_focused.get("label", ""))
	_focused = action
	if current_id() != old_id or current_label() != old_label:
		focused_action_changed.emit(current_label(), current_id())


func find_best_action() -> Dictionary:
	last_candidate_count = 0
	last_scanned_cells = 0
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return {}
	var eye: Vector3 = camera.global_position
	var candidates: Array[Dictionary] = []
	if is_instance_valid(quest):
		_append_provider_candidates(candidates, quest, eye)
	if is_instance_valid(streamer) and streamer.cell_size > 0.0:
		var center: Vector2i = streamer.cell_at_local_position(streamer.to_local(eye), streamer.cell_size)
		var around: int = clampi(ceili(max_query_distance / streamer.cell_size) + 1, 1, 4)
		for z in range(center.y - around, center.y + around + 1):
			for x in range(center.x - around, center.x + around + 1):
				var cell: Node3D = streamer.get_active_cell(Vector2i(x, z))
				if is_instance_valid(cell):
					last_scanned_cells += 1
					_append_provider_candidates(candidates, cell, eye)
	last_candidate_count = candidates.size()
	var facing: Vector3 = -camera.global_basis.z
	var selection: Dictionary = select_best(candidates, eye, facing,
		max_query_distance, min_view_dot)
	if not selection.is_empty() and require_line_of_sight and not _has_line_of_sight(selection):
		return {}
	return selection


func _append_provider_candidates(out: Array[Dictionary], provider: Node3D, eye: Vector3) -> void:
	if not provider.has_method("get_interaction_targets"):
		return
	var proposals: Variant = provider.call("get_interaction_targets", eye, max_query_distance)
	if typeof(proposals) != TYPE_ARRAY:
		return
	for proposal in proposals:
		if typeof(proposal) != TYPE_DICTIONARY:
			continue
		if not proposal.has("position") or not proposal.has("action_id"):
			continue
		var entry: Dictionary = proposal.duplicate()
		entry["provider"] = provider
		entry["uid"] = "%s:%s" % [str(provider.get_path()), str(entry["action_id"])]
		out.append(entry)


func _has_line_of_sight(action: Dictionary) -> bool:
	if not is_instance_valid(camera):
		return false
	var target_position: Vector3 = action.get("position", camera.global_position)
	var exceptions: Array[RID] = []
	if player is CollisionObject3D:
		exceptions.append((player as CollisionObject3D).get_rid())
	var parameters: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera.global_position, target_position, visibility_collision_mask, exceptions)
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(parameters)
	if hit.is_empty():
		return true
	var collider: Object = hit.get("collider")
	var target_collider: Node3D = action.get("target_collider")
	if is_instance_valid(target_collider) and collider is Node:
		if collider == target_collider or target_collider.is_ancestor_of(collider as Node):
			return true
	return (hit["position"] as Vector3).distance_to(camera.global_position) + 0.05 >= \
		target_position.distance_to(camera.global_position)


func try_interact() -> bool:
	# Always re-query: a focused scene may have been unloaded since the last tick.
	var action: Dictionary = find_best_action()
	_set_focus(action)
	if action.is_empty():
		return false
	var provider: Node3D = action.get("provider")
	if not is_instance_valid(provider) or not provider.has_method("activate_interaction"):
		return false
	var action_id: String = str(action.get("action_id", ""))
	var result: bool = provider.call("activate_interaction", action_id, player) == true
	var message: String = str(action.get("label", ""))
	if provider.has_method("get_interaction_message"):
		message = str(provider.call("get_interaction_message", action_id))
	interaction_completed.emit(str(action.get("uid", "")), result, message)
	refresh_focus()
	return result


func _on_cell_about_to_unload(_coord: Vector2i, cell: Node3D) -> void:
	if _focused.get("provider") == cell:
		_set_focus({})


## Pure choice helper. Invalid candidates, distance, view-angle and stale
## entries are rejected before any provider method is invoked.
static func select_best(candidates: Array[Dictionary], origin: Vector3,
		forward: Vector3, maximum_distance: float, view_dot: float) -> Dictionary:
	if maximum_distance <= 0.0 or forward.length_squared() < 0.00001:
		return {}
	var facing: Vector3 = forward.normalized()
	var best: Dictionary = {}
	var best_score: float = INF
	for candidate in candidates:
		if typeof(candidate.get("position")) != TYPE_VECTOR3:
			continue
		var position: Vector3 = candidate["position"]
		if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z):
			continue
		var radius: float = minf(maximum_distance, float(candidate.get("radius", maximum_distance)))
		if radius <= 0.0:
			continue
		var direction: Vector3 = position - origin
		var distance: float = direction.length()
		if distance > radius:
			continue
		var alignment: float = 1.0 if distance < 0.00001 else facing.dot(direction / distance)
		if alignment < view_dot:
			continue
		# Prefer center-of-view, then closer candidates; stable ID breaks ties.
		var score: float = distance + (1.0 - alignment) * 1.5
		if score < best_score - 0.0001 or (absf(score - best_score) <= 0.0001 \
				and str(candidate.get("uid", "")) < str(best.get("uid", "~"))):
			best_score = score
			best = candidate
	return best.duplicate()
