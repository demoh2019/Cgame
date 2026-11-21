extends RefCounted
## Facade over the input latency statistics. Prefers the native CgameLatencyProbe (modules/cgame_platform), which
## holds the samples, the pairing with photodiode edges and the percentile report, and falls back to the static
## helpers of scripts/client/input_latency_probe.gd. The Node of the legacy script (corner rectangle, input capture)
## stays in the game; it can feed a native probe through mark_input() / mark_draw().

const LEGACY = preload("res://scripts/client/input_latency_probe.gd")
const NATIVE_CLASS := &"CgameLatencyProbe"

static var _native_instance: Object = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _n() -> Object:
	if _native_instance == null:
		_native_instance = ClassDB.instantiate(NATIVE_CLASS)
	return _native_instance


## A native sample recorder, or null when the engine has no native module (use the legacy Node instead).
static func create_probe() -> Object:
	return ClassDB.instantiate(NATIVE_CLASS) if is_native() else null


static func latency_ms(sample: Dictionary, display_ms: float) -> float:
	return _n().latency_ms(sample, display_ms) if is_native() else LEGACY.latency_ms(sample, display_ms)


static func percentile(sorted_vals: PackedFloat64Array, p: float) -> float:
	return _n().percentile(sorted_vals, p) if is_native() else LEGACY.percentile(sorted_vals, p)


static func summarize(sample_list: Array, display_ms: float) -> Dictionary:
	return _n().summarize(sample_list, display_ms) if is_native() else LEGACY.summarize(sample_list, display_ms)


static func pair_photodiode(sample_list: Array, edges_us: PackedInt64Array, clock_offset_us: int = 0,
		max_gap_us: int = 500000) -> int:
	if is_native():
		return _n().pair_photodiode(sample_list, edges_us, clock_offset_us, max_gap_us)
	return LEGACY.pair_photodiode(sample_list, edges_us, clock_offset_us, max_gap_us)
