extends Control
## World Streaming Profiler (Ctrl+F3): live counters for the WorldStreamer and the world systems
## that stream around the player, plus a mini-map of chunk cells around you: loaded, loaded but
## still dressing (visual details pending), and not loaded.

const MAP_RADIUS := 6 # Cells each way.
const CELL_PX := 9.0

var streamer
var client
var far_field
var sea
var _history: PackedFloat32Array = PackedFloat32Array()
var _refresh := 0.0
var _lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-330, 70)
	size = Vector2(320, 430)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_history.append(delta * 1000.0)
	if _history.size() > 120:
		_history = _history.slice(_history.size() - 120)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_collect()
	queue_redraw()


func _count(method: String) -> String:
	return str(streamer.call(method)) if streamer != null and streamer.has_method(method) else "-"


func _collect() -> void:
	_lines = PackedStringArray()
	var worst := 0.0
	var total := 0.0
	for v in _history:
		worst = maxf(worst, v)
		total += v
	var avg: float = total / maxf(float(_history.size()), 1.0)
	_lines.append("WORLD STREAMING")
	_lines.append("frame %.1f ms avg, %.1f ms worst (2 s)" % [avg, worst])
	_lines.append("fps %d   draw calls %d" % [Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	_lines.append("loaded cells %s" % (str(streamer.get_loaded_cells().size()) if streamer != null else "-"))
	_lines.append("pending loads %s   queued gen %s" % [_count("get_pending_count"), _count("get_queued_generation_count")])
	_lines.append("visual details pending %s" % _count("get_pending_visual_details_count"))
	if streamer != null:
		_lines.append("radius load %.0f / unload %.0f m" % [streamer.load_radius, streamer.unload_radius])
	if far_field != null:
		_lines.append("far field: %s" % ("rebuilding row %d/%d" % [int(far_field._job["row"]), far_field.GRID] if not far_field._job.is_empty() else "ready"))
	if sea != null:
		_lines.append("sea depth map: %s" % ("ready" if sea.texture != null else "%d%%" % int(100.0 * float(sea._row) / float(sea.MAP_SIZE))))
	if client != null:
		var layers: Array = client.you.get("data_layers", [])
		_lines.append("data layers: %s" % (", ".join(layers) if not layers.is_empty() else "none"))
	_lines.append("objects %d   nodes %d" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	var font := ThemeDB.fallback_font
	var y := 18.0
	for line in _lines:
		draw_string(font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 0.85, 0.4) if line == "WORLD STREAMING" else Color(0.92, 0.95, 0.95))
		y += 17.0
	# Frame-time graph (16.7 ms line).
	var graph := Rect2(Vector2(10, y + 4), Vector2(size.x - 20, 46))
	draw_rect(graph, Color(1, 1, 1, 0.06))
	var limit_y: float = graph.end.y - graph.size.y * clampf(16.7 / 40.0, 0.0, 1.0)
	draw_line(Vector2(graph.position.x, limit_y), Vector2(graph.end.x, limit_y), Color(0.4, 1, 0.4, 0.4))
	for i in _history.size():
		var h: float = graph.size.y * clampf(_history[i] / 40.0, 0.0, 1.0)
		var x: float = graph.position.x + graph.size.x * float(i) / 120.0
		draw_line(Vector2(x, graph.end.y), Vector2(x, graph.end.y - h), Color(1, 0.4, 0.3) if _history[i] > 16.7 else Color(0.5, 0.85, 1.0))
	# Cell mini-map around the player.
	if streamer == null or client == null:
		return
	var here := Vector3(float(client.you.get("x", 0.0)), 0.0, float(client.you.get("z", 0.0)))
	var centre := Vector2i(floori(here.x / 64.0), floori(here.z / 64.0))
	var loaded: Dictionary = {}
	for cell in streamer.get_loaded_cells():
		loaded[Vector2i(cell.x, cell.z)] = streamer.get_chunk(cell)
	var map_origin := Vector2(size.x * 0.5 - CELL_PX * (MAP_RADIUS + 0.5), graph.end.y + 10)
	for dz in range(-MAP_RADIUS, MAP_RADIUS + 1):
		for dx in range(-MAP_RADIUS, MAP_RADIUS + 1):
			var key := Vector2i(centre.x + dx, centre.y + dz)
			var colour := Color(0.2, 0.2, 0.22)
			if loaded.has(key):
				colour = Color(0.3, 0.75, 0.35)
			draw_rect(Rect2(map_origin + Vector2(dx + MAP_RADIUS, dz + MAP_RADIUS) * CELL_PX, Vector2(CELL_PX - 1, CELL_PX - 1)), colour)
	draw_rect(Rect2(map_origin + Vector2(MAP_RADIUS, MAP_RADIUS) * CELL_PX, Vector2(CELL_PX - 1, CELL_PX - 1)), Color(1, 0.9, 0.3))
