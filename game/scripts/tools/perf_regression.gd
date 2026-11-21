extends RefCounted
## Performance regression comparison between two runs (e.g. two commits), with
## noise-aware aggregation (median of N runs) and a soak-test leak detector.
## Original code (MIT-compatible); statistics are textbook least squares.

const METRICS: Array[String] = [
	"frame_time_p50", "frame_time_p95", "frame_time_p99",
	"memory_peak", "draw_calls", "shader_compiles",
]
const DEFAULT_THRESHOLD_PCT: float = 10.0


## baseline/current: either a flat {metric: value} dict or {"runs": [flat dicts]}.
## thresholds: {metric_or_"default": max allowed % increase}; optional key
## "noise_factor" (default 0.5) widens the limit by that share of run spread.
static func compare_runs(baseline: Dictionary, current: Dictionary, thresholds: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var regressions: Array[String] = []
	var noise_factor: float = float(thresholds.get("noise_factor", 0.5))
	var default_pct: float = float(thresholds.get("default", DEFAULT_THRESHOLD_PCT))
	for m in METRICS:
		var b_vals: PackedFloat32Array = _values(baseline, m)
		var c_vals: PackedFloat32Array = _values(current, m)
		if b_vals.is_empty() or c_vals.is_empty():
			continue
		var b: float = _median(b_vals)
		var c: float = _median(c_vals)
		var pct: float = 0.0
		if absf(b) > 0.000001:
			pct = (c - b) / absf(b) * 100.0
		elif c > 0.0:
			pct = c * 100.0
		var noise: float = 0.0
		if absf(b) > 0.000001:
			noise = maxf(_spread(b_vals), _spread(c_vals)) / absf(b) * 100.0
		var limit: float = float(thresholds.get(m, default_pct)) + noise * noise_factor
		var regressed: bool = pct > limit
		out[m] = {
			"baseline": b, "current": c, "pct": pct, "limit": limit,
			"noise_pct": noise, "regressed": regressed,
			"improved": pct < -limit,
		}
		if regressed:
			regressions.append(m)
	return {"metrics": out, "regressions": regressions, "ok": regressions.is_empty()}


static func _values(d: Dictionary, metric: String) -> PackedFloat32Array:
	var vals: PackedFloat32Array = PackedFloat32Array()
	if d.has("runs"):
		var runs: Array = d["runs"]
		for r in runs:
			var rd: Dictionary = r
			if rd.has(metric):
				vals.append(float(rd[metric]))
	elif d.has(metric):
		vals.append(float(d[metric]))
	return vals


static func _median(v: PackedFloat32Array) -> float:
	var s: PackedFloat32Array = v.duplicate()
	s.sort()
	var n: int = s.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return s[n >> 1]
	return (s[(n >> 1) - 1] + s[n >> 1]) * 0.5


static func _spread(v: PackedFloat32Array) -> float:
	if v.size() < 2:
		return 0.0
	var lo: float = v[0]
	var hi: float = v[0]
	for x in v:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d: Dictionary = parsed
		return d
	return {}


static func save_json(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Least-squares slope of memory samples over a soak run. Flags a leak when the
## fit is strong (r2) and total growth exceeds min_growth_pct of the mean.
static func memory_leak_trend(samples: PackedFloat32Array, min_growth_pct: float = 5.0, min_r2: float = 0.8) -> Dictionary:
	var n: int = samples.size()
	if n < 3:
		return {"slope": 0.0, "r2": 0.0, "growth_pct": 0.0, "leak": false, "samples": n}
	var mx: float = float(n - 1) * 0.5
	var my: float = 0.0
	for y in samples:
		my += y
	my /= float(n)
	var sxx: float = 0.0
	var sxy: float = 0.0
	var syy: float = 0.0
	for i in n:
		var dx: float = float(i) - mx
		var dy: float = samples[i] - my
		sxx += dx * dx
		sxy += dx * dy
		syy += dy * dy
	var slope: float = sxy / sxx
	var r2: float = 0.0
	if syy > 0.0000001:
		r2 = (sxy * sxy) / (sxx * syy)
	var growth_pct: float = 0.0
	if absf(my) > 0.000001:
		growth_pct = slope * float(n - 1) / absf(my) * 100.0
	return {
		"slope": slope, "r2": r2, "growth_pct": growth_pct, "samples": n,
		"leak": slope > 0.0 and r2 >= min_r2 and growth_pct >= min_growth_pct,
	}
