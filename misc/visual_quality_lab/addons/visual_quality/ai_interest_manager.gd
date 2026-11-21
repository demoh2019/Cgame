extends Node
class_name WorldAIInterestManager3D
## Reusable interest-management / AI LOD manager for streamed scene roots.
## It throttles decisions about who simulates, without changing NavigationServer.

@export_range(5.0, 120.0, 1.0) var simulation_radius: float = 28.0
@export_range(1.0, 30.0, 1.0) var exit_margin: float = 8.0
@export_range(0.10, 3.0, 0.05) var update_interval_seconds: float = 0.45
@export_range(1, 32, 1) var max_cells_per_update: int = 8
@export var globally_enabled: bool = true

var streamer: WorldStreamer3D
var player: Node3D
var last_update_micros: int = 0
var peak_update_micros: int = 0
var _elapsed: float = 0.0
var _cursor: int = 0


func _ready() -> void:
	if is_instance_valid(streamer):
		streamer.cell_loaded.connect(_on_cell_loaded)
		for cell in streamer.get_active_cells():
			_apply_interest_to_cell(cell)


func _exit_tree() -> void:
	if is_instance_valid(streamer) and streamer.cell_loaded.is_connected(_on_cell_loaded):
		streamer.cell_loaded.disconnect(_on_cell_loaded)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= maxf(update_interval_seconds, 0.1):
		_elapsed = 0.0
		refresh_budgeted()


func _on_cell_loaded(_coord: Vector2i, cell: Node3D) -> void:
	_apply_interest_to_cell(cell)


func refresh_budgeted() -> void:
	if not is_instance_valid(streamer) or not is_instance_valid(player):
		return
	var begin: int = Time.get_ticks_usec()
	var cells: Array[Node3D] = streamer.get_active_cells()
	if cells.is_empty():
		_cursor = 0
		last_update_micros = Time.get_ticks_usec() - begin
		return
	var limit: int = mini(max_cells_per_update, cells.size())
	for i in range(limit):
		var index: int = (_cursor + i) % cells.size()
		_apply_interest_to_cell(cells[index])
	_cursor = (_cursor + limit) % cells.size()
	last_update_micros = Time.get_ticks_usec() - begin
	peak_update_micros = maxi(peak_update_micros, last_update_micros)


func _apply_interest_to_cell(cell: Node3D) -> void:
	if not is_instance_valid(cell) or not cell.has_method("set_ai_enabled"):
		return
	var enabled: bool = false
	if globally_enabled and is_instance_valid(player):
		var was_active: bool = cell.get("ai_enabled") == true
		var dist_squared: float = cell.global_position.distance_squared_to(player.global_position)
		enabled = should_simulate(dist_squared, was_active, simulation_radius, exit_margin)
	if cell.get("ai_enabled") != enabled:
		cell.call("set_ai_enabled", enabled)


func set_global_enabled(enabled: bool) -> void:
	globally_enabled = enabled
	if not is_instance_valid(streamer):
		return
	# Disabling AI is immediate. Re-enabling may be amortized.
	if not enabled:
		for cell in streamer.get_active_cells():
			if cell.has_method("set_ai_enabled"):
				cell.call("set_ai_enabled", false)
	else:
		_cursor = 0
		refresh_budgeted()


func set_quality_profile(profile: int) -> void:
	match clampi(profile, 0, 2):
		0:
			simulation_radius = 18.0
			max_cells_per_update = 6
		1:
			simulation_radius = 28.0
			max_cells_per_update = 8
		2:
			simulation_radius = 42.0
			max_cells_per_update = 12
	_cursor = 0
	refresh_budgeted()


func sleeping_npc_count() -> int:
	if not is_instance_valid(streamer):
		return 0
	var asleep: int = 0
	for cell in streamer.get_active_cells():
		if cell.has_method("get_active_npc") and cell.get("ai_enabled") != true:
			asleep += 1
	return asleep


static func should_simulate(distance_squared: float, was_active: bool,
		radius: float, margin: float) -> bool:
	if not is_finite(distance_squared) or distance_squared < 0.0:
		return false
	var threshold: float = maxf(radius, 0.0) + (maxf(margin, 0.0) if was_active else 0.0)
	return distance_squared <= threshold * threshold
