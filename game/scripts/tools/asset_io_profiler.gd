extends RefCounted
## Asset I/O timeline profiler: wraps ResourceLoader.load / load_threaded_request
## with timing and file sizes, and exports a timeline (entries or Chrome trace).
## Original code (MIT-compatible).

## Entry: {"path", "kind": "load"|"threaded", "start_usec", "dur_usec", "bytes", "ok", "ext"}
var entries: Array[Dictionary] = []
var _pending: Dictionary = {}  # path -> start_usec
var max_entries: int = 8192


func load_timed(path: String, type_hint: String = "") -> Resource:
	var t0: int = Time.get_ticks_usec()
	var res: Resource = ResourceLoader.load(path, type_hint)
	_record(path, "load", t0, Time.get_ticks_usec() - t0, res != null)
	return res


## Starts a threaded load; pair with poll() / get_threaded().
func request_threaded(path: String, type_hint: String = "") -> bool:
	var err: Error = ResourceLoader.load_threaded_request(path, type_hint)
	if err != OK:
		_record(path, "threaded", Time.get_ticks_usec(), 0, false)
		return false
	_pending[path] = Time.get_ticks_usec()
	return true


## Checks pending threaded loads; returns the paths that finished this call.
func poll() -> Array[String]:
	var done: Array[String] = []
	for key in _pending.keys():
		var path: String = str(key)
		var st: int = ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var t0: int = int(_pending[path])
		_record(path, "threaded", t0, Time.get_ticks_usec() - t0, st == ResourceLoader.THREAD_LOAD_LOADED)
		_pending.erase(path)
		done.append(path)
	return done


func pending_count() -> int:
	return _pending.size()


## Fetch a finished threaded resource (blocks if still loading).
func get_threaded(path: String) -> Resource:
	var res: Resource = ResourceLoader.load_threaded_get(path)
	if _pending.has(path):
		var t0: int = int(_pending[path])
		_record(path, "threaded", t0, Time.get_ticks_usec() - t0, res != null)
		_pending.erase(path)
	return res


func clear() -> void:
	entries.clear()
	_pending.clear()


func _record(path: String, kind: String, start: int, dur: int, ok: bool) -> void:
	if entries.size() >= max_entries:
		entries.pop_front()
	entries.append({
		"path": path, "kind": kind, "start_usec": start, "dur_usec": dur,
		"bytes": _file_size(path), "ok": ok, "ext": path.get_extension().to_lower(),
	})


static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n: int = f.get_length()
	f.close()
	return n


## Totals per extension: {ext: {count, total_usec, total_bytes, max_usec, mb_per_s}}.
func summary() -> Dictionary:
	var out: Dictionary = {}
	for e in entries:
		var ext: String = str(e["ext"])
		var s: Dictionary = out.get(ext, {"count": 0, "total_usec": 0, "total_bytes": 0, "max_usec": 0})
		s["count"] = int(s["count"]) + 1
		s["total_usec"] = int(s["total_usec"]) + int(e["dur_usec"])
		s["total_bytes"] = int(s["total_bytes"]) + int(e["bytes"])
		s["max_usec"] = maxi(int(s["max_usec"]), int(e["dur_usec"]))
		out[ext] = s
	for ext in out:
		var s: Dictionary = out[ext]
		var secs: float = float(int(s["total_usec"])) / 1000000.0
		s["mb_per_s"] = (float(int(s["total_bytes"])) / 1048576.0) / secs if secs > 0.0 else 0.0
	return out


## Slowest entries first.
func slowest(count: int = 10) -> Array[Dictionary]:
	var copy: Array[Dictionary] = entries.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["dur_usec"]) > int(b["dur_usec"]))
	return copy.slice(0, count)


## Timeline rows relative to the first entry (for a perf capture "trace_events" section).
func export_timeline() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if entries.is_empty():
		return out
	var base: int = int(entries[0]["start_usec"])
	for e in entries:
		out.append({
			"name": "io/" + str(e["path"]).get_file(), "cat": "asset_io", "ph": "X",
			"ts": int(e["start_usec"]) - base, "dur": int(e["dur_usec"]),
			"args": {"path": e["path"], "bytes": e["bytes"], "kind": e["kind"], "ok": e["ok"]},
		})
	return out


func export_chrome_json() -> String:
	var evs: Array = []
	for row in export_timeline():
		var r: Dictionary = row
		r["pid"] = 1
		r["tid"] = 2 if str(r["args"]["kind"]) == "threaded" else 1
		evs.append(r)
	return JSON.stringify({"traceEvents": evs})
