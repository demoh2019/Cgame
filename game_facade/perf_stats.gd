extends RefCounted
## Facade over the performance overlay's statistics core. Prefers the native CgamePerfStats
## (modules/cgame_platform) and falls back to PerfOverlay.PerfStats of scripts/client/perf_overlay.gd. Both objects
## have push, has_series, names, series, count, last, percentile, average, max_value and summary.

const LEGACY_OVERLAY = preload("res://scripts/client/perf_overlay.gd")
const NATIVE_CLASS := &"CgamePerfStats"


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Rolling statistics with `capacity` samples per series.
static func create(capacity: int = 300) -> Object:
	if is_native():
		var stats: Object = ClassDB.instantiate(NATIVE_CLASS)
		stats.capacity = capacity
		return stats
	return LEGACY_OVERLAY.PerfStats.new(capacity)
