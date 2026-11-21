extends Node
## Input-to-photon latency probe (normal rendering vs frame generation).
##
## How it works: every discrete input (key, mouse button, touch, joypad button) is timestamped
## with Time.get_ticks_usec() and a 32x32 corner rect is flipped black -> white. The first
## RenderingServer.frame_post_draw after the flip marks the moment the response was submitted.
##   software estimate = (post_draw - input) + half a refresh interval + display_offset_ms
## The estimate omits scan-out and pixel response; it is a proxy for comparing modes and
## builds, not an absolute number.
##
## Hardware photodiode workflow (absolute numbers, also correct with frame generation):
##   1. Tape a photodiode / phototransistor + microcontroller over the top-left 32x32 rect.
##   2. The controller timestamps each black -> white edge on its own clock (CSV, one
##      microsecond value per line) while the tester presses keys or clicks.
##   3. Call import_photodiode_csv(path, clock_offset_us). Each edge is paired with the latest
##      unmatched input before it; those samples then report photodiode - input latency.
## Frame generation: set_mode(MODE_FRAMEGEN) before the run (the engine cannot detect it) and
## compare per-mode percentiles in report(). Concepts follow PresentMon (MIT) "input to
## display" / click-to-photon definitions; all code is original (MIT-compatible).
##
## Usage: add as a child of any scene, call set_mode(), press inputs or run auto_probe().

signal sample_completed(sample: Dictionary)

const MODE_NORMAL: String = "normal"
const MODE_FRAMEGEN: String = "framegen"
const FLASH_SIZE: float = 32.0

var mode: String = MODE_NORMAL
var flash_frames: int = 3
var min_gap_ms: float = 80.0
## Extra display processing time added to software estimates (TV game mode ~ 5-15 ms).
var display_offset_ms: float = 0.0
var capture_enabled: bool = true
## {mode, input_us, draw_us, photodiode_us} ; draw_us / photodiode_us are -1 until known.
var samples: Array[Dictionary] = []

var _rect: ColorRect = null
var _pending: Array[int] = []
var _flash_left: int = 0
var _last_input_us: int = -1000000000


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 127
	add_child(layer)
	_rect = ColorRect.new()
	_rect.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	_rect.position = Vector2.ZERO
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_rect)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)


func set_mode(new_mode: String) -> void:
	mode = new_mode


func _input(event: InputEvent) -> void:
	if not capture_enabled:
		return
	var hit: bool = false
	if event is InputEventKey:
		var k: InputEventKey = event
		hit = k.pressed and not k.echo
	elif event is InputEventMouseButton:
		hit = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		hit = (event as InputEventScreenTouch).pressed
	elif event is InputEventJoypadButton:
		hit = (event as InputEventJoypadButton).pressed
	if hit:
		mark_input()


## Timestamps an input now and flashes the corner rect. Returns the sample index, or -1 when
## throttled by min_gap_ms.
func mark_input() -> int:
	var now: int = Time.get_ticks_usec()
	if float(now - _last_input_us) < min_gap_ms * 1000.0:
		return -1
	_last_input_us = now
	samples.append({"mode": mode, "input_us": now, "draw_us": -1, "photodiode_us": -1})
	_pending.append(samples.size() - 1)
	_flash_left = flash_frames
	if _rect != null:
		_rect.color = Color.WHITE
	return samples.size() - 1


func _on_post_draw() -> void:
	var now: int = Time.get_ticks_usec()
	for idx in _pending:
		samples[idx]["draw_us"] = now
		sample_completed.emit(samples[idx])
	_pending.clear()
	if _flash_left > 0:
		_flash_left -= 1
		if _flash_left == 0 and _rect != null:
			_rect.color = Color.BLACK


## Software-only run: injects `count` synthetic key presses `interval_s` apart. Awaitable.
func auto_probe(count: int, interval_s: float = 0.2) -> void:
	for i in count:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(interval_s).timeout


## Pairs photodiode edge timestamps (microseconds on the external clock) with samples.
## Returns the number of pairs made. See pair_photodiode().
func import_photodiode_csv(path: String, clock_offset_us: int = 0) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var edges: PackedInt64Array = PackedInt64Array()
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var s: String = line.strip_edges()
		if s.is_valid_int():
			edges.append(s.to_int())
	return pair_photodiode(samples, edges, clock_offset_us)


func report() -> Dictionary:
	var rep: Dictionary = summarize(samples, estimate_display_ms())
	rep["refresh_hz"] = DisplayServer.screen_get_refresh_rate()
	rep["display_offset_ms"] = display_offset_ms
	return rep


func estimate_display_ms() -> float:
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		hz = 60.0
	return 500.0 / hz + display_offset_ms


func save_report(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(report(), "\t"))
	f.close()
	return true


# ------------------------------------------------------------------ statistics (static, testable)

## Latency of one sample in ms, or -1.0 when incomplete. A photodiode time wins over the
## software estimate; software adds `display_ms` for scan-out.
static func latency_ms(s: Dictionary, display_ms: float) -> float:
	var input_us: int = int(s.get("input_us", -1))
	if input_us < 0:
		return -1.0
	var pd: int = int(s.get("photodiode_us", -1))
	if pd >= 0:
		return float(pd - input_us) / 1000.0
	var draw: int = int(s.get("draw_us", -1))
	if draw < 0:
		return -1.0
	return float(draw - input_us) / 1000.0 + display_ms


## Linear-interpolated percentile (p in 0..100) of an ascending-sorted array.
static func percentile(sorted_vals: PackedFloat64Array, p: float) -> float:
	var n: int = sorted_vals.size()
	if n == 0:
		return 0.0
	if n == 1:
		return sorted_vals[0]
	var pos: float = clampf(p, 0.0, 100.0) / 100.0 * float(n - 1)
	var lo: int = int(floor(pos))
	var hi: int = mini(lo + 1, n - 1)
	return lerpf(sorted_vals[lo], sorted_vals[hi], pos - float(lo))


## Per-mode statistics: {mode: {count, min, avg, p50, p90, p95, p99, max, jitter, source}}.
## "source" is "photodiode" when every sample has one, "mixed" for some, otherwise "software".
static func summarize(sample_list: Array, display_ms: float) -> Dictionary:
	var by_mode: Dictionary = {}
	var pd_count: Dictionary = {}
	for s_v in sample_list:
		var s: Dictionary = s_v
		var ms: float = latency_ms(s, display_ms)
		if ms < 0.0:
			continue
		var m: String = str(s.get("mode", MODE_NORMAL))
		if not by_mode.has(m):
			by_mode[m] = PackedFloat64Array()
			pd_count[m] = 0
		var arr: PackedFloat64Array = by_mode[m]
		arr.append(ms)
		by_mode[m] = arr
		if int(s.get("photodiode_us", -1)) >= 0:
			pd_count[m] = int(pd_count[m]) + 1
	var out: Dictionary = {}
	for m in by_mode.keys():
		var a: PackedFloat64Array = by_mode[m]
		a.sort()
		var total: float = 0.0
		for v in a:
			total += v
		var avg: float = total / float(a.size())
		var var_sum: float = 0.0
		for v in a:
			var_sum += (v - avg) * (v - avg)
		var src: String = "software"
		if int(pd_count[m]) == a.size():
			src = "photodiode"
		elif int(pd_count[m]) > 0:
			src = "mixed"
		out[m] = {
			"count": a.size(), "min": a[0], "avg": avg, "p50": percentile(a, 50.0),
			"p90": percentile(a, 90.0), "p95": percentile(a, 95.0), "p99": percentile(a, 99.0),
			"max": a[a.size() - 1], "jitter": sqrt(var_sum / float(a.size())), "source": src,
		}
	return out


## Assigns each photodiode edge (external clock, + clock_offset_us to map to the engine clock)
## to the latest unmatched sample whose input precedes it by at most max_gap_us.
static func pair_photodiode(sample_list: Array[Dictionary], edges_us: PackedInt64Array,
		clock_offset_us: int = 0, max_gap_us: int = 500000) -> int:
	var paired: int = 0
	for e in edges_us:
		var t: int = e + clock_offset_us
		var best: int = -1
		for i in sample_list.size():
			var s: Dictionary = sample_list[i]
			if int(s["photodiode_us"]) >= 0:
				continue
			var in_us: int = int(s["input_us"])
			if in_us <= t and t - in_us <= max_gap_us:
				if best < 0 or in_us > int(sample_list[best]["input_us"]):
					best = i
		if best >= 0:
			sample_list[best]["photodiode_us"] = t
			paired += 1
	return paired
