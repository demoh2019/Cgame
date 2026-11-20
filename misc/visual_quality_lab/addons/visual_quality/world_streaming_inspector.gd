extends CanvasLayer
class_name WorldStreamingInspector3D
## Lightweight in-game view of spatial streaming and per-cell CPU hotspots.
## It polls bounded diagnostics; it never owns/instantiates game world cells.

@export_range(1, 6, 1) var grid_radius: int = 4
@export_range(0.1, 3.0, 0.1) var refresh_interval: float = 0.4
@export var hotspot_csv_path: String = "user://visual_quality_cell_hotspots.csv"

var streamer: WorldStreamer3D
var _panel: PanelContainer
var _text: Label
var _elapsed: float = 0.0


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.name = "StreamingInspectorPanel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -345.0
	_panel.offset_right = -18.0
	_panel.offset_top = 20.0
	add_child(_panel)
	_text = Label.new()
	_text.name = "StreamingInspectorText"
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9))
	_panel.add_child(_text)
	refresh()


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(streamer):
		return
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= refresh_interval:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_instance_valid(_text):
		return
	if not is_instance_valid(streamer) or not is_instance_valid(streamer.source):
		_text.text = "STREAMING INSPECTOR: no streaming source"
		return
	var center: Vector2i = streamer.cell_at_local_position(
		streamer.to_local(streamer.source.global_position), streamer.cell_size)
	var header: String = "STREAMING INSPECTOR  |  K hide  |  L export\n"
	header += "@ player   # active   + predicted   . unloaded\n"
	var grid: String = ""
	for z in range(center.y + grid_radius, center.y - grid_radius - 1, -1):
		for x in range(center.x - grid_radius, center.x + grid_radius + 1):
			var coord: Vector2i = Vector2i(x, z)
			var mark: String = " "
			if coord == center:
				mark = "@"
			elif streamer.get_active_cell(coord) != null:
				mark = "#"
			elif streamer.last_predicted_cell == coord:
				mark = "+"
			elif streamer.is_cell_registered(coord):
				mark = "."
			grid += mark + " "
		grid += "\n"
	var footer: String = "Active: %d   Prefetched: %d   Waiting assets: %d\n" % [
		streamer.active_cell_count(), streamer.total_prefetched_count,
		streamer.pending_asset_count()]
	footer += "Refresh: %d us   Budget: %d us   Peaks: %d\n" % [
		streamer.last_update_micros, streamer.max_spawn_time_usec_per_update,
		streamer.profiled_cell_count()]
	footer += "Slowest cell spawns (CPU, includes scene ready):\n"
	for entry in streamer.get_slowest_cells(3):
		var coord: Vector2i = entry["coord"]
		footer += "(%d,%d)  peak %d us / last %d us\n" % [
			coord.x, coord.y, int(entry["peak_spawn_us"]),
			int(entry["last_spawn_us"])]
	_text.text = header + grid + footer


func toggle_visible() -> void:
	visible = not visible
	if visible:
		refresh()


func export_hotspot_csv() -> Error:
	if not hotspot_csv_path.begins_with("user://"):
		return ERR_INVALID_PARAMETER
	if not is_instance_valid(streamer):
		return ERR_DOES_NOT_EXIST
	var file: FileAccess = FileAccess.open(hotspot_csv_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_csv_line(PackedStringArray([
		"cell_x", "cell_z", "spawns", "unloads", "last_spawn_us",
		"peak_spawn_us", "last_unload_us"
	]))
	for entry in streamer.get_slowest_cells(streamer.max_profiled_cells):
		var coord: Vector2i = entry["coord"]
		file.store_csv_line(PackedStringArray([
			str(coord.x), str(coord.y), str(entry["spawn_count"]),
			str(entry["unload_count"]), str(entry["last_spawn_us"]),
			str(entry["peak_spawn_us"]), str(entry["last_unload_us"])
		]))
	file.close()
	return OK
