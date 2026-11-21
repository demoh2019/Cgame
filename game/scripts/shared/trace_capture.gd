extends RefCounted
## Unreal-Insights-style trace capture with Chrome / Perfetto trace export and frame-regression comparison.
##
## Format reference: "Trace Event Format" (Chrome / catapult project, BSD-3-Clause documentation),
## consumed by chrome://tracing, ui.perfetto.dev (Apache-2.0) and speedscope (MIT).
## Design inspired by the scope/counter/frame-marker model of Tracy (BSD-3-Clause) and
## Unreal Insights (concepts only; no code copied). Implementation is original.
##
## Usage:
##   var tr := TraceCapture.new(); tr.enabled = true
##   tr.begin("physics"); ...; tr.end()          # nested scopes per thread
##   tr.measure("ai", func(): return think())    # scope around a callable
##   tr.frame_marker(Engine.get_process_frames())
##   tr.save("user://trace.json")                # open in ui.perfetto.dev
##   TraceCapture.compare(baseline_stats, tr.frame_stats(), 10.0)
##
## Scopes are stored as complete ("X") events written when the scope ends, so a ring buffer that
## overwrites old events can never leave an orphaned begin/end pair.

## Master switch. When false every recording call returns immediately.
var enabled: bool = false
## Ring buffer capacity in events; the oldest events are overwritten.
var max_events: int = 65536
## Number of per-frame records kept for frame_stats().
var max_frames: int = 4096

var _mutex := Mutex.new()
var _events: Array = []
var _head: int = 0
var _stacks: Dictionary = {}  # tid -> Array of [name, category, start_usec]
var _thread_names: Dictionary = {}  # tid -> String
var _frames: Array = []  # {"index", "ms", "scopes": {name: usec}, "counters": {name: value}}
var _frame_scopes: Dictionary = {}
var _frame_counters: Dictionary = {}
var _last_frame_usec: int = -1


## Opens a scope on the calling thread.
func begin(name: String, category: String = "game") -> void:
	if not enabled:
		return
	var tid: int = OS.get_thread_caller_id()
	var now: int = Time.get_ticks_usec()
	_mutex.lock()
	if not _stacks.has(tid):
		_stacks[tid] = []
	var stack: Array = _stacks[tid]
	stack.append([name, category, now])
	_mutex.unlock()


## Closes the innermost open scope on the calling thread (no-op if none).
func end() -> void:
	if not enabled:
		return
	var tid: int = OS.get_thread_caller_id()
	var now: int = Time.get_ticks_usec()
	_mutex.lock()
	var stack: Array = _stacks.get(tid, [])
	if not stack.is_empty():
		var open: Array = stack.pop_back()
		var started: int = open[2]
		var scope_name: String = open[0]
		var dur: int = maxi(now - started, 0)
		_push({"ph": "X", "name": scope_name, "cat": open[1], "ts": started, "dur": dur, "tid": tid})
		_frame_scopes[scope_name] = int(_frame_scopes.get(scope_name, 0)) + dur
	_mutex.unlock()


## Runs `callable` inside a scope and returns its result.
func measure(name: String, callable: Callable, category: String = "game") -> Variant:
	if not enabled:
		return callable.call()
	begin(name, category)
	var result: Variant = callable.call()
	end()
	return result


func counter(name: String, value: float) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_usec()
	_mutex.lock()
	_push({"ph": "C", "name": name, "cat": "counter", "ts": now, "tid": OS.get_thread_caller_id(), "args": {name: value}})
	_frame_counters[name] = value
	_mutex.unlock()


func instant(name: String, args: Dictionary = {}) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_usec()
	_mutex.lock()
	_push({"ph": "i", "name": name, "cat": "instant", "ts": now, "tid": OS.get_thread_caller_id(), "args": args})
	_mutex.unlock()


## Marks a frame boundary and closes the per-frame aggregates used by frame_stats().
func frame_marker(frame_index: int) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_usec()
	_mutex.lock()
	if _last_frame_usec >= 0:
		_frames.append({
			"index": frame_index,
			"ms": float(now - _last_frame_usec) / 1000.0,
			"scopes": _frame_scopes,
			"counters": _frame_counters,
		})
		if _frames.size() > max_frames:
			_frames.pop_front()
	_last_frame_usec = now
	_frame_scopes = {}
	_frame_counters = {}
	_push({"ph": "i", "name": "frame", "cat": "frame", "ts": now, "tid": OS.get_thread_caller_id(), "args": {"frame": frame_index}})
	_mutex.unlock()


## Starts a flow arrow (task hand-off); pair with flow_end(id, name) on the consuming thread.
func flow_start(id: int, name: String) -> void:
	_flow("s", id, name)


func flow_end(id: int, name: String) -> void:
	_flow("f", id, name)


func set_thread_name(name: String) -> void:
	_mutex.lock()
	_thread_names[OS.get_thread_caller_id()] = name
	_mutex.unlock()


func event_count() -> int:
	_mutex.lock()
	var n: int = _events.size()
	_mutex.unlock()
	return n


func clear() -> void:
	_mutex.lock()
	_events.clear()
	_head = 0
	_stacks.clear()
	_frames.clear()
	_frame_scopes = {}
	_frame_counters = {}
	_last_frame_usec = -1
	_mutex.unlock()


## Frames as consumed by HitchCorrelator.correlate(): [{"ms", "scopes", "counters", "index"}].
func frames() -> Array:
	_mutex.lock()
	var copy: Array = _frames.duplicate(true)
	_mutex.unlock()
	return copy


## Chrome Trace Event Format JSON (open in chrome://tracing or ui.perfetto.dev).
func export_chrome_json() -> String:
	_mutex.lock()
	var ordered: Array = []
	var count: int = _events.size()
	for i in count:
		ordered.append(_events[(_head + i) % count])
	var names: Dictionary = _thread_names.duplicate()
	_mutex.unlock()

	# Stable chronological order; at equal start a longer scope comes first so parents enclose children.
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = a["ts"]
		var tb: int = b["ts"]
		if ta != tb:
			return ta < tb
		return int(a.get("dur", 0)) > int(b.get("dur", 0)))

	var pid: int = OS.get_process_id()
	var main_tid: int = OS.get_main_thread_id()
	var out: Array = [{"ph": "M", "name": "process_name", "pid": pid, "tid": main_tid, "args": {"name": "Cgame"}}]
	var seen: Dictionary = {}
	for ev: Dictionary in ordered:
		seen[int(ev["tid"])] = true
	for tid in seen:
		var label: String = names.get(tid, "main" if tid == main_tid else "thread-%d" % tid)
		out.append({"ph": "M", "name": "thread_name", "pid": pid, "tid": tid, "args": {"name": label}})
	for ev: Dictionary in ordered:
		var rec: Dictionary = {"ph": ev["ph"], "name": ev["name"], "cat": ev["cat"], "ts": ev["ts"], "pid": pid, "tid": ev["tid"]}
		if ev.has("dur"):
			rec["dur"] = ev["dur"]
		if ev.has("args"):
			rec["args"] = ev["args"]
		if ev.has("id"):
			rec["id"] = ev["id"]
		match String(ev["ph"]):
			"i":
				rec["s"] = "t"
			"f":
				rec["bp"] = "e"
		out.append(rec)
	return JSON.stringify({"traceEvents": out, "displayTimeUnit": "ms"})


func save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(export_chrome_json())
	f.close()
	return true


## Per-scope totals over captured frames: {"frames": n, "scopes": {name: {"total", "avg", "max"}}} in usec.
func frame_stats() -> Dictionary:
	_mutex.lock()
	var frame_list: Array = _frames
	var n: int = frame_list.size()
	var scopes: Dictionary = {}
	for fr: Dictionary in frame_list:
		var per: Dictionary = fr["scopes"]
		for scope_name in per:
			var usec: float = float(per[scope_name])
			if not scopes.has(scope_name):
				scopes[scope_name] = {"total": 0.0, "avg": 0.0, "max": 0.0}
			var s: Dictionary = scopes[scope_name]
			s["total"] = float(s["total"]) + usec
			s["max"] = maxf(float(s["max"]), usec)
	_mutex.unlock()
	for scope_name in scopes:
		var s: Dictionary = scopes[scope_name]
		s["avg"] = float(s["total"]) / float(maxi(n, 1))
	return {"frames": n, "scopes": scopes}


func save_stats_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(frame_stats(), "\t"))
	f.close()
	return true


## Returns {} when the file is missing or malformed.
static func load_stats_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


## Scopes whose average frame cost grew by more than threshold_pct versus the baseline,
## worst first: [{"scope", "baseline_avg", "current_avg", "pct"}]. New/zero-baseline scopes are skipped.
static func compare(baseline: Dictionary, current: Dictionary, threshold_pct: float = 10.0) -> Array:
	var report: Array = []
	var base_scopes: Dictionary = baseline.get("scopes", {})
	var cur_scopes: Dictionary = current.get("scopes", {})
	for scope_name in cur_scopes:
		if not base_scopes.has(scope_name):
			continue
		var base_avg: float = float(Dictionary(base_scopes[scope_name]).get("avg", 0.0))
		var cur_avg: float = float(Dictionary(cur_scopes[scope_name]).get("avg", 0.0))
		if base_avg <= 0.0:
			continue
		var pct: float = (cur_avg - base_avg) / base_avg * 100.0
		if pct > threshold_pct:
			report.append({"scope": scope_name, "baseline_avg": base_avg, "current_avg": cur_avg, "pct": pct})
	report.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pct"]) > float(b["pct"]))
	return report


func _flow(ph: String, id: int, name: String) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_usec()
	_mutex.lock()
	_push({"ph": ph, "name": name, "cat": "flow", "ts": now, "tid": OS.get_thread_caller_id(), "id": id})
	_mutex.unlock()


## Caller must hold the mutex.
func _push(ev: Dictionary) -> void:
	var cap: int = maxi(max_events, 1)
	if _events.size() < cap:
		_events.append(ev)
		return
	if _events.size() > cap:
		# Capacity was lowered at runtime: keep the newest `cap` events.
		var ordered: Array = []
		for i in _events.size():
			ordered.append(_events[(_head + i) % _events.size()])
		_events = ordered.slice(ordered.size() - cap)
		_head = 0
	_events[_head] = ev
	_head = (_head + 1) % cap
