@tool
extends Control
## Sequencer-style cinematic timeline editor panel.
## Data model: scripts/client/cinematic_sequence.gd; preview: cinematic_player.gd.
## All editing goes through the public API below (usable headless); the mouse
## UI in _gui_input only calls that API.
##
## Design inspired by Unreal Sequencer / Unity Timeline (UI ideas only; no code
## copied). License of this file: MIT.

signal changed
signal time_changed(t: float)

const CinematicSequence = preload("res://scripts/client/cinematic_sequence.gd")
const CinematicPlayer = preload("res://scripts/client/cinematic_player.gd")

const KINDS: PackedStringArray = ["transform", "float", "event", "animation"]
const HEADER_W: float = 180.0
const TOOLBAR_H: float = 26.0
const RULER_H: float = 24.0
const ROW_H: float = 22.0
const KEY_HIT: float = 6.0
const MAX_UNDO: int = 100

var sequence: CinematicSequence = null
var player: CinematicPlayer = null
var fps: float = 30.0
var pixels_per_second: float = 80.0
var scroll_x: float = 0.0
var current_time: float = 0.0
var blend_seconds: float = 0.0
var selected_track: Dictionary = {}
var selected_key: int = -1

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

var _drag_mode: String = ""  # "", "scrub", "key", "shot"
var _drag_shot: int = -1
var _drag_key_time: float = 0.0

var _toolbar: HBoxContainer = null


func _init() -> void:
	player = CinematicPlayer.new()
	add_child(player)
	sequence = CinematicSequence.new()
	player.sequence = sequence
	custom_minimum_size = Vector2(400, 200)
	clip_contents = true
	_build_toolbar()


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.position = Vector2(0, 0)
	add_child(_toolbar)
	var defs: Array = [
		["Undo", undo], ["Redo", redo],
		["+Shot", _ui_add_shot], ["+Transform", _ui_add_track.bind("transform")],
		["+Float", _ui_add_track.bind("float")], ["+Event", _ui_add_track.bind("event")],
		["+Anim", _ui_add_track.bind("animation")], ["+FOV", _ui_add_track.bind("float", "fov")],
		["+Focus", _ui_add_track.bind("float", "focus_distance")],
	]
	for d in defs:
		var pair: Array = d
		var b := Button.new()
		b.text = String(pair[0])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(pair[1] as Callable)
		_toolbar.add_child(b)


func _ui_add_shot() -> void:
	var start: float = 0.0
	if not sequence.shots.is_empty():
		start = float((sequence.shots[sequence.shots.size() - 1] as Dictionary)["end"])
	add_shot(start, start + 2.0, "cam%d" % (sequence.shots.size() + 1))


func _ui_add_track(kind: String, track_name: String = "") -> void:
	var n: String = track_name if track_name != "" else "%s%d" % [kind, _store(kind).size() + 1]
	add_track(kind, n)


# ---------------------------------------------------------------- API

func open(seq: CinematicSequence) -> void:
	sequence = seq
	player.play(seq, player.bindings)
	player.stop()
	_undo_stack.clear()
	_redo_stack.clear()
	selected_track = {}
	selected_key = -1
	current_time = 0.0
	queue_redraw()
	changed.emit()


func bind(binding_name: String, node: Node) -> void:
	player.bindings[binding_name] = node


func _store(kind: String) -> Dictionary:
	match kind:
		"transform":
			return sequence.transform_tracks
		"float":
			return sequence.float_tracks
		"event":
			return sequence.event_tracks
		"animation":
			return sequence.animation_tracks
	return {}


func _keys(track: Dictionary) -> Array:
	var store: Dictionary = _store(String(track.get("kind", "")))
	var tn: String = String(track.get("name", ""))
	if not store.has(tn):
		return []
	return store[tn]


## Track descriptors, in display order: [{"kind", "name"}].
func list_tracks() -> Array:
	var out: Array = []
	for kind in KINDS:
		for tn in _store(kind).keys():
			out.append({"kind": kind, "name": String(tn)})
	return out


func add_track(kind: String, track_name: String) -> Dictionary:
	if not KINDS.has(kind) or track_name == "":
		return {}
	var store: Dictionary = _store(kind)
	if not store.has(track_name):
		_push_undo()
		store[track_name] = []
		_after_edit()
	return {"kind": kind, "name": track_name}


func delete_track(track: Dictionary) -> void:
	var store: Dictionary = _store(String(track.get("kind", "")))
	var tn: String = String(track.get("name", ""))
	if store.has(tn):
		_push_undo()
		store.erase(tn)
		selected_key = -1
		_after_edit()


## value: transform -> Transform3D or {"position","rotation"[,"interp"]};
## float -> float or {"value","ease"}; event -> String or {"name","args"};
## animation -> {"target","animation"}. Returns the new key's index.
func add_key(track: Dictionary, time: float, value: Variant) -> int:
	var kind: String = String(track.get("kind", ""))
	var tn: String = String(track.get("name", ""))
	var store: Dictionary = _store(kind)
	if store.is_empty() and not KINDS.has(kind):
		return -1
	_push_undo()
	if not store.has(tn):
		store[tn] = []
	var arr: Array = store[tn]
	var idx: int = _sorted_index(arr, time)
	match kind:
		"transform":
			var kd: Dictionary = {"time": time, "interp": "linear"}
			if value is Transform3D:
				var xf: Transform3D = value
				kd["position"] = xf.origin
				kd["rotation"] = xf.basis.get_rotation_quaternion()
			elif value is Dictionary:
				kd.merge(value as Dictionary, true)
				kd["time"] = time
			sequence.add_transform_key(tn, kd)
		"float":
			if value is Dictionary:
				var fd: Dictionary = (value as Dictionary).duplicate()
				fd["time"] = time
				sequence.add_float_key(tn, fd)
			else:
				sequence.add_float_key(tn, {"time": time, "value": float(value)})
		"event":
			if value is Dictionary:
				var ed: Dictionary = value
				sequence.add_event(tn, time, String(ed.get("name", "")), ed.get("args", []) as Array)
			else:
				sequence.add_event(tn, time, String(value))
		"animation":
			var ad: Dictionary = value if value is Dictionary else {}
			sequence.add_animation_key(tn, time, String(ad.get("target", "")), String(ad.get("animation", "")))
	selected_track = track
	selected_key = idx
	_after_edit()
	return idx


func move_key(track: Dictionary, index: int, new_time: float) -> int:
	var arr: Array = _keys(track)
	if index < 0 or index >= arr.size():
		return -1
	_push_undo()
	var key: Dictionary = arr.pop_at(index)
	key["time"] = maxf(new_time, 0.0)
	var idx: int = _sorted_index(arr, float(key["time"]))
	arr.insert(idx, key)
	if selected_track == track:
		selected_key = idx
	_after_edit()
	return idx


func delete_key(track: Dictionary, index: int) -> void:
	var arr: Array = _keys(track)
	if index < 0 or index >= arr.size():
		return
	_push_undo()
	arr.remove_at(index)
	selected_key = -1
	_after_edit()


func key_count(track: Dictionary) -> int:
	return _keys(track).size()


func key_at(track: Dictionary, index: int) -> Dictionary:
	var arr: Array = _keys(track)
	if index < 0 or index >= arr.size():
		return {}
	return arr[index]


static func _sorted_index(arr: Array, t: float) -> int:
	var i: int = arr.size()
	while i > 0 and float((arr[i - 1] as Dictionary)["time"]) > t:
		i -= 1
	return i


func add_shot(start: float, end: float, camera: String) -> void:
	_push_undo()
	sequence.add_shot(start, end, camera)
	if end > sequence.length:
		sequence.length = end
	_after_edit()


func delete_shot(index: int) -> void:
	if index < 0 or index >= sequence.shots.size():
		return
	_push_undo()
	sequence.shots.remove_at(index)
	_after_edit()


## Nonlinear edit: moves shot `from` to position `to` in the shot order. Shots
## are re-packed (gaps before each shot travel with it) so following shots
## ripple, and every key inside a shot's old range moves with that shot.
func reorder_shot(from: int, to: int) -> void:
	var n: int = sequence.shots.size()
	if from < 0 or from >= n or to < 0 or to >= n or from == to:
		return
	_push_undo()
	var old: Array = []  # per shot: {start, end, camera, gap}
	var cursor: float = float((sequence.shots[0] as Dictionary)["start"])
	var origin: float = cursor
	for s in sequence.shots:
		var sd: Dictionary = s
		var st: float = sd["start"]
		old.append({"start": st, "end": sd["end"], "camera": sd["camera"], "gap": maxf(st - cursor, 0.0)})
		cursor = maxf(cursor, float(sd["end"]))
	var order: Array = []
	for i in n:
		order.append(i)
	order.remove_at(from)
	order.insert(to, from)
	var deltas: Array = []
	deltas.resize(n)
	var new_shots: Array = []
	var pos: float = origin
	for oi in order:
		var o: Dictionary = old[int(oi)]
		pos += float(o["gap"])
		var dur: float = float(o["end"]) - float(o["start"])
		deltas[int(oi)] = pos - float(o["start"])
		new_shots.append({"start": pos, "end": pos + dur, "camera": o["camera"]})
		pos += dur
	for kind in KINDS:
		var store: Dictionary = _store(kind)
		for tn in store.keys():
			var arr: Array = store[tn]
			for k in arr:
				var kd: Dictionary = k
				var kt: float = kd["time"]
				for i in n:
					var o2: Dictionary = old[i]
					if kt >= float(o2["start"]) and kt < float(o2["end"]):
						kd["time"] = kt + float(deltas[i])
						break
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	sequence.shots = new_shots
	_after_edit()


func snap_time(t: float) -> float:
	if fps <= 0.0:
		return t
	return roundf(t * fps) / fps


## Moves the playhead and applies the sequence to bound nodes via the player.
func scrub(t: float) -> void:
	current_time = clampf(t, 0.0, sequence.length)
	player.sequence = sequence
	player.seek(current_time)
	queue_redraw()
	time_changed.emit(current_time)


## {"from","to","weight"} for the camera-cut blend at time t (uses blend_seconds).
func blend_preview(t: float) -> Dictionary:
	return sequence.camera_cut_blend(t, blend_seconds)


func add_lens_key(time: float, fov_degrees: float) -> int:
	return add_key(add_track("float", "fov"), time, fov_degrees)


# ---------------------------------------------------------- undo / redo

func _push_undo() -> void:
	_undo_stack.append(_snapshot())
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _snapshot() -> Dictionary:
	return sequence.to_dict()


func _restore(d: Dictionary) -> void:
	var tmp: CinematicSequence = CinematicSequence.from_dict(d) as CinematicSequence
	sequence.length = tmp.length
	sequence.shots = tmp.shots
	sequence.transform_tracks = tmp.transform_tracks
	sequence.float_tracks = tmp.float_tracks
	sequence.event_tracks = tmp.event_tracks
	sequence.animation_tracks = tmp.animation_tracks
	# from_dict drops empty tracks; keep them so a track list survives undo/save.
	var empties: Dictionary = {
		"transform_tracks": sequence.transform_tracks, "float_tracks": sequence.float_tracks,
		"event_tracks": sequence.event_tracks, "animation_tracks": sequence.animation_tracks,
	}
	for field in empties.keys():
		var dst: Dictionary = empties[field]
		var src: Dictionary = d.get(field, {})
		for tn in src.keys():
			if not dst.has(tn):
				dst[tn] = []
	selected_key = -1


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_snapshot())
	_restore(_undo_stack.pop_back())
	_after_edit(false)


func redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_snapshot())
	_restore(_redo_stack.pop_back())
	_after_edit(false)


func _after_edit(_dirty: bool = true) -> void:
	queue_redraw()
	changed.emit()


# ------------------------------------------------------------ save / load

func save(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(sequence.to_dict()))
	f.close()
	return true


@warning_ignore("shadowed_global_identifier")
func load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	var d: Dictionary = parsed
	var seq: CinematicSequence = CinematicSequence.from_dict(d) as CinematicSequence
	for field in ["transform_tracks", "float_tracks", "event_tracks", "animation_tracks"]:
		var src: Dictionary = d.get(field, {})
		var dst: Dictionary = seq.get(field)
		for tn in src.keys():
			if not dst.has(tn):
				dst[tn] = []
	open(seq)
	return true


# --------------------------------------------------------------- drawing

func _time_to_x(t: float) -> float:
	return HEADER_W + t * pixels_per_second - scroll_x


func _x_to_time(x: float) -> float:
	return (x - HEADER_W + scroll_x) / pixels_per_second


func _row_y(row: int) -> float:
	return TOOLBAR_H + RULER_H + float(row) * ROW_H


func _kind_color(kind: String) -> Color:
	match kind:
		"transform":
			return Color(0.45, 0.75, 1.0)
		"float":
			return Color(0.6, 1.0, 0.5)
		"event":
			return Color(1.0, 0.7, 0.3)
	return Color(0.9, 0.5, 0.9)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _draw() -> void:
	if sequence == null:
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = 11
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.16))
	# ruler
	draw_rect(Rect2(HEADER_W, TOOLBAR_H, size.x - HEADER_W, RULER_H), Color(0.18, 0.19, 0.22))
	var step: float = 1.0
	for s in [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]:
		step = float(s)
		if step * pixels_per_second >= 50.0:
			break
	var t0: float = floorf(maxf(_x_to_time(HEADER_W), 0.0) / step) * step
	var t: float = t0
	while _time_to_x(t) < size.x and t <= sequence.length + step:
		var x: float = _time_to_x(t)
		draw_line(Vector2(x, TOOLBAR_H + RULER_H - 8.0), Vector2(x, size.y), Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(x + 3.0, TOOLBAR_H + 14.0), "%.2fs" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.8, 0.8))
		t += step
	# end of sequence
	var ex: float = _time_to_x(sequence.length)
	draw_line(Vector2(ex, TOOLBAR_H), Vector2(ex, size.y), Color(1, 0.3, 0.3, 0.6))
	# shot row
	var shot_y: float = _row_y(0)
	draw_string(font, Vector2(6.0, shot_y + 15.0), "Shots", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
	for i in sequence.shots.size():
		var sd: Dictionary = sequence.shots[i]
		var x0: float = _time_to_x(float(sd["start"]))
		var x1: float = _time_to_x(float(sd["end"]))
		var r := Rect2(x0, shot_y + 2.0, x1 - x0, ROW_H - 4.0)
		draw_rect(r, Color(0.3, 0.45, 0.7, 0.85) if i != _drag_shot else Color(0.8, 0.6, 0.2, 0.85))
		draw_rect(r, Color(1, 1, 1, 0.5), false)
		draw_string(font, Vector2(x0 + 4.0, shot_y + 15.0), String(sd["camera"]), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 6.0, fs, Color(1, 1, 1))
		# camera-cut blend zone
		if i > 0 and blend_seconds > 0.0:
			var bx: float = _time_to_x(float(sd["start"]) + blend_seconds)
			draw_rect(Rect2(x0, shot_y + ROW_H - 6.0, minf(bx, x1) - x0, 4.0), Color(1, 1, 0.3, 0.8))
	# tracks
	var tracks: Array = list_tracks()
	for row in tracks.size():
		var trk: Dictionary = tracks[row]
		var y: float = _row_y(row + 1)
		var kind: String = trk["kind"]
		var sel: bool = trk == selected_track
		if sel:
			draw_rect(Rect2(0, y, size.x, ROW_H), Color(1, 1, 1, 0.06))
		draw_line(Vector2(0, y + ROW_H), Vector2(size.x, y + ROW_H), Color(1, 1, 1, 0.06))
		draw_string(font, Vector2(6.0, y + 15.0), "[%s] %s" % [kind.substr(0, 1), String(trk["name"])], HORIZONTAL_ALIGNMENT_LEFT, HEADER_W - 8.0, fs, _kind_color(kind))
		var arr: Array = _keys(trk)
		for ki in arr.size():
			var kt: float = (arr[ki] as Dictionary)["time"]
			if sel and _drag_mode == "key" and ki == selected_key:
				kt = _drag_key_time
			var c := Vector2(_time_to_x(kt), y + ROW_H * 0.5)
			var col: Color = Color(1, 1, 1) if (sel and ki == selected_key) else _kind_color(kind)
			_diamond(c, 5.0, col)
	# header divider + playhead
	draw_line(Vector2(HEADER_W, TOOLBAR_H), Vector2(HEADER_W, size.y), Color(1, 1, 1, 0.25))
	var px: float = _time_to_x(current_time)
	draw_line(Vector2(px, TOOLBAR_H), Vector2(px, size.y), Color(1, 0.2, 0.2))
	draw_colored_polygon(PackedVector2Array([Vector2(px - 5, TOOLBAR_H), Vector2(px + 5, TOOLBAR_H), Vector2(px, TOOLBAR_H + 9)]), Color(1, 0.2, 0.2))


# ----------------------------------------------------------------- input

func _track_at_y(y: float) -> Dictionary:
	var row: int = int(floor((y - TOOLBAR_H - RULER_H) / ROW_H)) - 1
	var tracks: Array = list_tracks()
	if row < 0 or row >= tracks.size():
		return {}
	return tracks[row]


func _shot_at_time(t: float) -> int:
	for i in sequence.shots.size():
		var sd: Dictionary = sequence.shots[i]
		if t >= float(sd["start"]) and t < float(sd["end"]):
			return i
	return -1


func _key_hit(track: Dictionary, x: float) -> int:
	var arr: Array = _keys(track)
	for i in arr.size():
		if absf(_time_to_x(float((arr[i] as Dictionary)["time"])) - x) <= KEY_HIT:
			return i
	return -1


func _default_value(track: Dictionary, t: float) -> Variant:
	var kind: String = track["kind"]
	var tn: String = track["name"]
	match kind:
		"transform":
			var bound: Variant = player.bindings.get(tn, null)
			if bound is Node3D:
				return (bound as Node3D).transform
			return sequence.sample_transform(tn, t)
		"float":
			return sequence.sample_float(tn, t)
		"event":
			return "event"
	return {"target": "", "animation": ""}


func _gui_input(event: InputEvent) -> void:
	if sequence == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.ctrl_pressed:
			pixels_per_second = minf(pixels_per_second * 1.15, 1000.0)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.ctrl_pressed:
			pixels_per_second = maxf(pixels_per_second / 1.15, 10.0)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb)
			else:
				_release(mb)
	elif event is InputEventMouseMotion:
		_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_DELETE and selected_key >= 0 and not selected_track.is_empty():
			delete_key(selected_track, selected_key)


func _press(mb: InputEventMouseButton) -> void:
	var p: Vector2 = mb.position
	if p.y < TOOLBAR_H or p.x < HEADER_W and p.y < TOOLBAR_H + RULER_H:
		return
	if p.y < TOOLBAR_H + RULER_H:
		_drag_mode = "scrub"
		scrub(snap_time(_x_to_time(p.x)))
		return
	if p.y < _row_y(1):
		var si: int = _shot_at_time(_x_to_time(p.x))
		if si >= 0:
			_drag_mode = "shot"
			_drag_shot = si
			queue_redraw()
		return
	var trk: Dictionary = _track_at_y(p.y)
	selected_track = trk
	selected_key = -1
	if not trk.is_empty() and p.x >= HEADER_W:
		var hit: int = _key_hit(trk, p.x)
		if hit >= 0:
			selected_key = hit
			_drag_mode = "key"
			_drag_key_time = float((_keys(trk)[hit] as Dictionary)["time"])
		elif mb.double_click:
			var tt: float = snap_time(maxf(_x_to_time(p.x), 0.0))
			add_key(trk, tt, _default_value(trk, tt))
	queue_redraw()


func _motion(mm: InputEventMouseMotion) -> void:
	match _drag_mode:
		"scrub":
			scrub(snap_time(_x_to_time(mm.position.x)))
		"key":
			_drag_key_time = maxf(snap_time(_x_to_time(mm.position.x)), 0.0)
			queue_redraw()


func _release(mb: InputEventMouseButton) -> void:
	var mode: String = _drag_mode
	_drag_mode = ""
	if mode == "key" and selected_key >= 0:
		if not is_equal_approx(float(key_at(selected_track, selected_key).get("time", 0.0)), _drag_key_time):
			move_key(selected_track, selected_key, _drag_key_time)
	elif mode == "shot":
		var from: int = _drag_shot
		_drag_shot = -1
		var to: int = _shot_at_time(_x_to_time(mb.position.x))
		if to >= 0 and to != from:
			reorder_shot(from, to)
	queue_redraw()
