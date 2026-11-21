extends CanvasLayer
## Unified in-game performance panel: frame/GPU/process/physics time, draw calls, VRAM, static
## memory, object/node counts, pipeline compilations and custom sources (streaming queues, ...),
## with rolling graphs, p50/p95/p99 stats, budget lines and hitch markers labelled with their cause.
##
## Design references (ideas only, no code copied): Unreal `stat unit` / Insights live view and the
## Unity Profiler overlay. Percentile math is the standard linear-interpolation definition.
## Original implementation for this project.
##
## Cost model: every frame pushes ~10 floats into fixed ring buffers (no allocation); the panel
## only redraws at REDRAW_HZ and only while visible.
##
##   var perf := preload("res://scripts/client/perf_overlay.gd").new()
##   add_child(perf); perf.add_source("stream_queue", func() -> float: return float(q.size()))
##   perf.toggle()  # F3        perf.cycle_mode()  # Shift+F3

enum Mode { COMPACT, FULL, GRAPHS }

const FrameHitchAnalyzer = preload("res://scripts/client/frame_hitch_analyzer.gd")
const HitchCorrelator = preload("res://scripts/shared/hitch_correlator.gd")

const HISTORY := 300 # frames kept per series
const STATS_WINDOW := 300 # frames used for percentiles
const REDRAW_HZ := 10.0
const BUDGET_60 := 16.6
const BUDGET_30 := 33.3
const MAX_MARKERS := 32
const GRAPH_W := 240.0
const GRAPH_H := 38.0
const PAD := 8.0

## Built-in series: name -> [label, unit, is_time_ms]
const BUILTIN: Array = [
	["frame_ms", "Frame", "ms", true],
	["gpu_ms", "GPU", "ms", true],
	["process_ms", "Process", "ms", true],
	["physics_ms", "Physics", "ms", true],
	["draw_calls", "Draws", "", false],
	["vram_mb", "VRAM", "MB", false],
	["mem_static_mb", "Mem", "MB", false],
	["objects", "Objects", "", false],
	["nodes", "Nodes", "", false],
	["pipelines", "Pipelines", "", false],
]


## Fixed-capacity ring of floats.
class Ring extends RefCounted:
	var data: PackedFloat32Array
	var head: int = 0
	var count: int = 0
	var total: int = 0

	func _init(capacity: int) -> void:
		data.resize(maxi(capacity, 1))

	func push(v: float) -> void:
		data[head] = v
		head = (head + 1) % data.size()
		count = mini(count + 1, data.size())
		total += 1

	## Oldest-to-newest copy of the last `n` values (all when n <= 0).
	func to_array(n: int = 0) -> PackedFloat32Array:
		var take: int = count if n <= 0 else mini(n, count)
		var out := PackedFloat32Array()
		out.resize(take)
		var start: int = (head - take + data.size() * 2) % data.size()
		for i in take:
			out[i] = data[(start + i) % data.size()]
		return out


## Headless-testable rolling statistics keyed by series name.
class PerfStats extends RefCounted:
	var capacity: int
	var _rings: Dictionary = {}

	func _init(p_capacity: int = 300) -> void:
		capacity = maxi(p_capacity, 1)

	func push(series_name: String, value: float) -> void:
		if not is_finite(value):
			return
		var ring: Ring
		if _rings.has(series_name):
			ring = _rings[series_name]
		else:
			ring = Ring.new(capacity)
			_rings[series_name] = ring
		ring.push(value)

	func has_series(series_name: String) -> bool:
		return _rings.has(series_name)

	func names() -> Array:
		return _rings.keys()

	func series(series_name: String, window: int = 0) -> PackedFloat32Array:
		if not _rings.has(series_name):
			return PackedFloat32Array()
		var ring: Ring = _rings[series_name]
		return ring.to_array(window)

	func count(series_name: String) -> int:
		if not _rings.has(series_name):
			return 0
		var ring: Ring = _rings[series_name]
		return ring.count

	func last(series_name: String) -> float:
		var s := series(series_name, 1)
		return 0.0 if s.is_empty() else s[0]

	## Linear-interpolated percentile, p in [0, 100], over the last `window` samples.
	func percentile(series_name: String, p: float, window: int = 0) -> float:
		var s := series(series_name, window)
		if s.is_empty():
			return 0.0
		s.sort()
		var rank: float = clampf(p, 0.0, 100.0) / 100.0 * float(s.size() - 1)
		var lo: int = int(floorf(rank))
		var hi: int = mini(lo + 1, s.size() - 1)
		return lerpf(s[lo], s[hi], rank - float(lo))

	func average(series_name: String, window: int = 0) -> float:
		var s := series(series_name, window)
		if s.is_empty():
			return 0.0
		var sum := 0.0
		for v in s:
			sum += v
		return sum / float(s.size())

	func max_value(series_name: String, window: int = 0) -> float:
		var s := series(series_name, window)
		var m := 0.0
		for v in s:
			m = maxf(m, v)
		return m

	func summary(series_name: String, window: int = 0) -> Dictionary:
		return {"last": last(series_name), "avg": average(series_name, window),
			"p50": percentile(series_name, 50.0, window), "p95": percentile(series_name, 95.0, window),
			"p99": percentile(series_name, 99.0, window), "max": max_value(series_name, window),
			"samples": count(series_name)}


## Draws the panel; the overlay owns all state.
class Canvas extends Control:
	var overlay: Node

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if overlay != null:
			overlay.call("_paint", self)


var stats := PerfStats.new(HISTORY)
var mode: int = Mode.COMPACT
var hitch_analyzer := FrameHitchAnalyzer.new()
var trace: RefCounted ## Optional TraceCapture for per-scope hitch culprits in snapshot().
var loaded_cells_source: Callable ## Optional Callable -> int feeding hitch cause "streaming".
var hitch_markers: Array[Dictionary] = []
var frame_index: int = 0

var _sources: Dictionary = {} # name -> Callable
var _canvas: Canvas
var _redraw_accum: float = 0.0
var _gpu_measuring: bool = false


func _init() -> void:
	layer = 128
	visible = false


func _ready() -> void:
	_canvas = Canvas.new()
	_canvas.overlay = self
	add_child(_canvas)


## Registers a custom monitor (e.g. streaming queue size). The Callable must return a number.
func add_source(source_name: String, source: Callable) -> void:
	_sources[source_name] = source


func remove_source(source_name: String) -> void:
	_sources.erase(source_name)


func toggle() -> void:
	visible = not visible
	_set_gpu_measure(visible)
	if visible and _canvas != null:
		_canvas.queue_redraw()


func cycle_mode() -> int:
	mode = (mode + 1) % 3
	if _canvas != null:
		_canvas.queue_redraw()
	return mode


func mode_name() -> String:
	return ["compact", "full", "graphs"][mode]


## Feeds a hitch record from an external FrameHitchAnalyzer ({"ms","cause","time",...}).
func record_hitch(hitch: Dictionary) -> void:
	if hitch.is_empty():
		return
	var marker: Dictionary = {"frame": frame_index, "ms": float(hitch.get("ms", 0.0)),
		"cause": String(hitch.get("cause", "cpu")), "time": float(hitch.get("time", 0.0))}
	hitch_markers.append(marker)
	if hitch_markers.size() > MAX_MARKERS:
		hitch_markers.pop_front()


func _process(delta: float) -> void:
	sample(delta)
	if not visible:
		return
	_redraw_accum += delta
	if _redraw_accum >= 1.0 / REDRAW_HZ:
		_redraw_accum = 0.0
		if _canvas != null:
			_canvas.queue_redraw()


## Samples every monitor once. Public so tests and headless tools can drive it.
func sample(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	frame_index += 1
	stats.push("frame_ms", delta * 1000.0)
	stats.push("process_ms", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	stats.push("physics_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	stats.push("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	stats.push("mem_static_mb", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	stats.push("objects", Performance.get_monitor(Performance.OBJECT_COUNT))
	stats.push("nodes", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var cells: int = 0
	if loaded_cells_source.is_valid():
		cells = int(loaded_cells_source.call())
	var counters: Dictionary = FrameHitchAnalyzer.read_counters(cells)
	stats.push("vram_mb", float(counters["vram"]) / 1048576.0)
	stats.push("pipelines", float(counters["compiles"]))
	if is_inside_tree() and visible:
		var vp: Viewport = get_viewport()
		if vp != null:
			stats.push("gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	for source_name: String in _sources:
		var source: Callable = _sources[source_name]
		if source.is_valid():
			stats.push(source_name, float(source.call()))
	record_hitch(hitch_analyzer.sample(delta, counters, float(Time.get_ticks_msec()) / 1000.0))


## Machine-readable state for bug reports.
func snapshot() -> Dictionary:
	var series_stats: Dictionary = {}
	for series_name: String in stats.names():
		series_stats[series_name] = stats.summary(series_name, STATS_WINDOW)
	var out: Dictionary = {"frame_index": frame_index, "mode": mode_name(), "stats": series_stats,
		"hitches": hitch_markers.duplicate(true), "hitch_counts": hitch_analyzer.counts.duplicate(),
		"sources": _sources.keys(), "engine": Engine.get_version_info().get("string", ""),
		"fps": Engine.get_frames_per_second()}
	if trace != null and trace.has_method("frames") and trace.has_method("frame_stats"):
		var frames: Array = trace.call("frames")
		out["trace_hitches"] = HitchCorrelator.correlate(frames, BUDGET_30)
		out["trace_scopes"] = trace.call("frame_stats")
	return out


func _set_gpu_measure(on: bool) -> void:
	if on == _gpu_measuring or not is_inside_tree():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), on)
	_gpu_measuring = on


func _paint(c: Control) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = 12
	var x: float = PAD
	var y: float = PAD
	var panel_w: float = GRAPH_W + PAD * 2.0
	var fr: Dictionary = stats.summary("frame_ms", STATS_WINDOW)
	var fps: float = 1000.0 / maxf(float(fr["avg"]), 0.001)
	var head: String = "%.0f fps  %.1f ms  p95 %.1f  p99 %.1f  [%s]" % [fps, fr["last"], fr["p95"], fr["p99"], mode_name()]
	var rows: Array = []
	if mode == Mode.COMPACT:
		rows = []
	elif mode == Mode.FULL:
		rows = ["frame_ms", "gpu_ms", "process_ms", "physics_ms", "draw_calls", "vram_mb", "mem_static_mb", "nodes"]
	else:
		rows = ["frame_ms", "gpu_ms", "process_ms", "draw_calls", "vram_mb", "mem_static_mb", "objects", "nodes", "pipelines"]
	rows.append_array(_sources.keys())
	var height: float = PAD * 2.0 + 16.0
	if mode == Mode.FULL:
		height += float(rows.size()) * 15.0 + 16.0 + GRAPH_H
	elif mode == Mode.GRAPHS:
		height += float(rows.size()) * (GRAPH_H + 16.0)
	c.draw_rect(Rect2(0.0, 0.0, panel_w, height), Color(0, 0, 0, 0.62))
	var tint: Color = Color(0.4, 1.0, 0.5) if float(fr["p95"]) <= BUDGET_60 else (Color(1.0, 0.85, 0.3) if float(fr["p95"]) <= BUDGET_30 else Color(1.0, 0.4, 0.35))
	c.draw_string(font, Vector2(x, y + 12.0), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
	y += 18.0
	if mode == Mode.FULL:
		for row: String in rows:
			var s: Dictionary = stats.summary(row, STATS_WINDOW)
			var line: String = "%-13s %8.2f  p50 %.2f  p95 %.2f  p99 %.2f" % [_label(row), s["last"], s["p50"], s["p95"], s["p99"]]
			c.draw_string(font, Vector2(x, y + 11.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(0.9, 0.9, 0.9))
			y += 15.0
		y += 4.0
		_graph(c, font, "frame_ms", Rect2(x, y, GRAPH_W, GRAPH_H), true)
		y += GRAPH_H + 12.0
		c.draw_string(font, Vector2(x, y + 8.0), hitch_summary(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(1.0, 0.7, 0.4))
	elif mode == Mode.GRAPHS:
		for row: String in rows:
			c.draw_string(font, Vector2(x, y + 10.0), "%s %.2f" % [_label(row), stats.last(row)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(0.85, 0.85, 0.85))
			y += 13.0
			_graph(c, font, row, Rect2(x, y, GRAPH_W, GRAPH_H), row == "frame_ms")
			y += GRAPH_H + 3.0


func hitch_summary() -> String:
	var counts: Dictionary = hitch_analyzer.counts
	return "hitches: shaders %d  streaming %d  vram %d  cpu %d" % [
		counts["shader_compile"], counts["streaming"], counts["vram"], counts["cpu"]]


func _label(series_name: String) -> String:
	for spec: Array in BUILTIN:
		if String(spec[0]) == series_name:
			return String(spec[1])
	return series_name


func _is_time(series_name: String) -> bool:
	for spec: Array in BUILTIN:
		if String(spec[0]) == series_name:
			return bool(spec[3])
	return false


func _graph(c: Control, font: Font, series_name: String, r: Rect2, markers: bool) -> void:
	c.draw_rect(r, Color(1, 1, 1, 0.06))
	var s: PackedFloat32Array = stats.series(series_name)
	if s.size() < 2:
		return
	var is_time: bool = _is_time(series_name)
	var top: float = maxf(stats.max_value(series_name), 1.0)
	if is_time:
		top = maxf(top, BUDGET_30 * 1.2)
	var step: float = r.size.x / float(HISTORY - 1)
	var pts := PackedVector2Array()
	var x0: float = r.position.x + r.size.x - step * float(s.size() - 1)
	for i in s.size():
		pts.append(Vector2(x0 + step * float(i), r.end.y - clampf(s[i] / top, 0.0, 1.0) * r.size.y))
	c.draw_polyline(pts, Color(0.45, 0.85, 1.0), 1.0)
	if is_time:
		for budget: float in [BUDGET_60, BUDGET_30]:
			var by: float = r.end.y - budget / top * r.size.y
			c.draw_line(Vector2(r.position.x, by), Vector2(r.end.x, by), Color(1, 1, 1, 0.28), 1.0)
			c.draw_string(font, Vector2(r.position.x + 2.0, by - 1.0), "%.1f" % budget, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
	if markers:
		for m: Dictionary in hitch_markers:
			var age: int = frame_index - int(m["frame"])
			if age >= s.size():
				continue
			var mx: float = x0 + step * float(s.size() - 1 - age)
			c.draw_line(Vector2(mx, r.position.y), Vector2(mx, r.end.y), Color(1.0, 0.4, 0.3, 0.8), 1.0)
			c.draw_string(font, Vector2(mx + 2.0, r.position.y + 9.0), String(m["cause"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.6, 0.4))
