extends RefCounted
## Facade for CgameTrace (native, modules/cgame_profiling) with the GDScript TraceCapture as fallback.
##
## Drop-in replacement for scripts/shared/trace_capture.gd: `TraceCapture.new()` keeps working.
## With the native class every instance shares the engine singleton (one set of per-thread ring
## buffers and automatic per-frame markers); the fallback is a private GDScript instance.

const FALLBACK_PATH := "res://scripts/shared/trace_capture.gd"

var _impl: Object = null
var _native: bool = false

## Master switch. When false every recording call returns immediately.
var enabled: bool:
	get:
		return _impl != null and _impl.enabled
	set(value):
		if _impl != null:
			_impl.enabled = value

## Ring buffer capacity in events (per thread when native).
var max_events: int:
	get:
		return _impl.max_events if _impl != null else 0
	set(value):
		if _impl != null:
			_impl.max_events = value

## Number of per-frame records kept for frame_stats().
var max_frames: int:
	get:
		return _impl.max_frames if _impl != null else 0
	set(value):
		if _impl != null:
			_impl.max_frames = value


func _init() -> void:
	if Engine.has_singleton("CgameTrace"):
		_impl = Engine.get_singleton("CgameTrace")
		_native = true
	elif ResourceLoader.exists(FALLBACK_PATH):
		_impl = (load(FALLBACK_PATH) as GDScript).new()
	else:
		push_error("TraceCapture facade: neither CgameTrace nor %s is available" % FALLBACK_PATH)


## True when backed by the native engine singleton.
func is_native() -> bool:
	return _native


func begin(name: String, category: String = "game") -> void:
	if _impl != null:
		_impl.begin(name, category)


func end() -> void:
	if _impl != null:
		_impl.end()


func measure(name: String, callable: Callable, category: String = "game") -> Variant:
	if _impl == null:
		return callable.call()
	return _impl.measure(name, callable, category)


func counter(name: String, value: float) -> void:
	if _impl != null:
		_impl.counter(name, value)


func instant(name: String, args: Dictionary = {}) -> void:
	if _impl != null:
		_impl.instant(name, args)


func frame_marker(frame_index: int) -> void:
	if _impl != null:
		_impl.frame_marker(frame_index)


func flow_start(id: int, name: String) -> void:
	if _impl != null:
		_impl.flow_start(id, name)


func flow_end(id: int, name: String) -> void:
	if _impl != null:
		_impl.flow_end(id, name)


func set_thread_name(name: String) -> void:
	if _impl != null:
		_impl.set_thread_name(name)


func event_count() -> int:
	return _impl.event_count() if _impl != null else 0


func clear() -> void:
	if _impl != null:
		_impl.clear()


func frames() -> Array:
	return Array(_impl.frames()) if _impl != null else []


func export_chrome_json() -> String:
	return _impl.export_chrome_json() if _impl != null else "{}"


func save(path: String) -> bool:
	return _impl != null and _impl.save(path)


func frame_stats() -> Dictionary:
	return _impl.frame_stats() if _impl != null else {"frames": 0, "scopes": {}}


func save_stats_json(path: String) -> bool:
	return _impl != null and _impl.save_stats_json(path)


static func load_stats_json(path: String) -> Dictionary:
	if Engine.has_singleton("CgameTrace"):
		return Engine.get_singleton("CgameTrace").load_stats_json(path)
	if ResourceLoader.exists(FALLBACK_PATH):
		return (load(FALLBACK_PATH) as GDScript).load_stats_json(path)
	return {}


static func compare(baseline: Dictionary, current: Dictionary, threshold_pct: float = 10.0) -> Array:
	if Engine.has_singleton("CgameTrace"):
		# Static native methods are reachable through the singleton instance.
		return Engine.get_singleton("CgameTrace").call("compare", baseline, current, threshold_pct)
	if ResourceLoader.exists(FALLBACK_PATH):
		return (load(FALLBACK_PATH) as GDScript).compare(baseline, current, threshold_pct)
	return []
