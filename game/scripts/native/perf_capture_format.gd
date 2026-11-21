extends RefCounted
## Facade for CgamePerfCapture (native) with scripts/tools/perf_capture_format.gd and
## scripts/tools/perf_regression.gd as GDScript fallbacks. All methods are static.

const FORMAT_FALLBACK := "res://scripts/tools/perf_capture_format.gd"
const REGRESSION_FALLBACK := "res://scripts/tools/perf_regression.gd"
const VERSION: int = 1
const MAGIC: String = "cgperf"


static func is_native() -> bool:
	return ClassDB.class_exists("CgamePerfCapture")


static func _n() -> Object:
	return ClassDB.instantiate("CgamePerfCapture")


static func _format() -> GDScript:
	return load(FORMAT_FALLBACK) as GDScript if ResourceLoader.exists(FORMAT_FALLBACK) else null


static func _regression() -> GDScript:
	return load(REGRESSION_FALLBACK) as GDScript if ResourceLoader.exists(REGRESSION_FALLBACK) else null


static func new_capture(label: String = "") -> Dictionary:
	if is_native():
		return _n().call("new_capture", label)
	var f := _format()
	return f.new_capture(label) if f != null else {}


static func capture_environment() -> Dictionary:
	if is_native():
		return _n().call("capture_environment")
	var f := _format()
	return f.capture_environment() if f != null else {}


## Capture whose frames come from the live CgameTrace (native only; empty frames otherwise).
static func capture_from_trace(label: String = "") -> Dictionary:
	if is_native():
		return _n().call("capture_from_trace", label)
	return new_capture(label)


static func add_frame(cap: Dictionary, index: int, ms: float, scopes: Dictionary = {}, counters: Dictionary = {}) -> void:
	if is_native():
		_n().call("add_frame", cap, index, ms, scopes, counters)
		return
	var f := _format()
	if f != null:
		f.add_frame(cap, index, ms, scopes, counters)


static func add_event(cap: Dictionary, section: String, ev: Dictionary) -> void:
	if is_native():
		_n().call("add_event", cap, section, ev)
		return
	var f := _format()
	if f != null:
		f.add_event(cap, section, ev)


## Human-readable problems; empty means valid. Always an Array of Strings.
static func validate(cap: Dictionary) -> Array:
	if is_native():
		return Array(_n().call("validate", cap))
	var f := _format()
	return Array(f.validate(cap)) if f != null else ["no backend"]


static func write(path: String, cap: Dictionary, as_json: bool = false) -> bool:
	if is_native():
		return _n().call("write", path, cap, as_json)
	var f := _format()
	return f != null and f.write(path, cap, as_json)


static func read(path: String) -> Dictionary:
	if is_native():
		return _n().call("read", path)
	var f := _format()
	return f.read(path) if f != null else {}


static func merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	if is_native():
		return _n().call("merge", base, extra)
	var f := _format()
	return f.merge(base, extra) if f != null else base


static func frame_times(cap: Dictionary) -> PackedFloat32Array:
	if is_native():
		return _n().call("frame_times", cap)
	var f := _format()
	return f.frame_times(cap) if f != null else PackedFloat32Array()


static func compare_runs(baseline: Dictionary, current: Dictionary, thresholds: Dictionary = {}) -> Dictionary:
	if is_native():
		return _n().call("compare_runs", baseline, current, thresholds)
	var r := _regression()
	return r.compare_runs(baseline, current, thresholds) if r != null else {}


## Scopes whose average frame cost grew between two captures (native only).
static func compare_subsystems(baseline_capture: Dictionary, current_capture: Dictionary, threshold_pct: float = 10.0) -> Array:
	if is_native():
		return _n().call("compare_subsystems", baseline_capture, current_capture, threshold_pct)
	return []


static func memory_leak_trend(samples: PackedFloat32Array, min_growth_pct: float = 5.0, min_r2: float = 0.8) -> Dictionary:
	if is_native():
		return _n().call("memory_leak_trend", samples, min_growth_pct, min_r2)
	var r := _regression()
	return r.memory_leak_trend(samples, min_growth_pct, min_r2) if r != null else {}


static func load_json(path: String) -> Dictionary:
	if is_native():
		return _n().call("load_json", path)
	var r := _regression()
	return r.load_json(path) if r != null else {}


static func save_json(path: String, data: Dictionary) -> bool:
	if is_native():
		return _n().call("save_json", path, data)
	var r := _regression()
	return r != null and r.save_json(path, data)
