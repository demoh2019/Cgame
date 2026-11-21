extends RefCounted
## Explains frame hitches: for each frame slower than a threshold, names the scopes that grew most
## versus the rolling median of preceding frames and the counters that jumped.
## Original implementation (median-baseline attribution as used by common frame profilers).

const WINDOW := 60
const TOP_SCOPES := 3


## frames: [{"ms": float, "scopes": {name: usec}, "counters": {name: value}}]
## Returns [{"index", "ms", "baseline_ms", "culprits": [{"scope","usec","median_usec","growth_usec"}],
## "counters": [{"name","value","median"}]}] in frame order.
static func correlate(frames: Array, threshold_ms: float) -> Array:
	var result: Array = []
	for i in frames.size():
		var frame: Dictionary = frames[i]
		var ms: float = float(frame.get("ms", 0.0))
		if ms <= threshold_ms:
			continue
		var from: int = maxi(0, i - WINDOW)
		var window: Array = frames.slice(from, i)
		var ms_values: Array = []
		for w: Dictionary in window:
			ms_values.append(float(w.get("ms", 0.0)))
		var baseline_ms: float = _median(ms_values) if not window.is_empty() else ms

		var culprits: Array = []
		var scopes: Dictionary = frame.get("scopes", {})
		for scope_name in scopes:
			var usec: float = float(scopes[scope_name])
			var med: float = _median(_series(window, "scopes", scope_name))
			if usec - med > 0.0:
				culprits.append({"scope": scope_name, "usec": usec, "median_usec": med, "growth_usec": usec - med})
		culprits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["growth_usec"]) > float(b["growth_usec"]))
		if culprits.size() > TOP_SCOPES:
			culprits.resize(TOP_SCOPES)

		var jumped: Array = []
		var counters: Dictionary = frame.get("counters", {})
		for counter_name in counters:
			var value: float = float(counters[counter_name])
			var med: float = _median(_series(window, "counters", counter_name))
			if absf(value - med) > maxf(absf(med) * 0.5, 1.0):
				jumped.append({"name": counter_name, "value": value, "median": med})
		result.append({"index": i, "ms": ms, "baseline_ms": baseline_ms, "culprits": culprits, "counters": jumped})
	return result


static func _series(window: Array, key: String, name: Variant) -> Array:
	var values: Array = []
	for w: Dictionary in window:
		var d: Dictionary = w.get(key, {})
		values.append(float(d.get(name, 0.0)))
	return values


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var mid: int = n >> 1
	if n % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5
