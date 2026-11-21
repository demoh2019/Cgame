extends RefCounted
## GPU family database -> recommended quality level (0 low .. 3 ultra), resolution scale and
## feature toggles. Matches by regex on the adapter name; measured results learned at runtime
## (user://gpu_learned.json) override the static heuristic using the median frame time per level.
## Original code (MIT-compatible).

const MAX_LEVEL: int = 3
const DEFAULT_PATH: String = "user://gpu_learned.json"
const MAX_SAMPLES_PER_LEVEL: int = 31
const TARGET_FRAME_MS: float = 1000.0 / 60.0

## Ordered rules, first match wins: {pattern, family, level, scale}.
const RULES: Array[Dictionary] = [
	# Apple silicon
	{"pattern": "apple m[1-4] (max|ultra)", "family": "apple_m_pro_max", "level": 3, "scale": 1.0},
	{"pattern": "apple m[2-4] pro", "family": "apple_m_pro_max", "level": 3, "scale": 1.0},
	{"pattern": "apple m1 pro", "family": "apple_m1_pro", "level": 2, "scale": 1.0},
	{"pattern": "apple m[34]\\b", "family": "apple_m3_m4", "level": 3, "scale": 1.0},
	{"pattern": "apple m2\\b", "family": "apple_m2", "level": 2, "scale": 1.0},
	{"pattern": "apple m1\\b", "family": "apple_m1", "level": 2, "scale": 0.9},
	{"pattern": "apple a(1[5-9]|[2-9]\\d)", "family": "apple_a_new", "level": 1, "scale": 0.8},
	{"pattern": "apple a\\d+", "family": "apple_a_old", "level": 0, "scale": 0.7},
	# NVIDIA
	{"pattern": "rtx\\s*[2-5]0(90|80|70)", "family": "nvidia_rtx_high", "level": 3, "scale": 1.0},
	{"pattern": "rtx\\s*[3-5]0(60|50)", "family": "nvidia_rtx_mid", "level": 2, "scale": 1.0},
	{"pattern": "rtx\\s*20(60|50)", "family": "nvidia_rtx20_mid", "level": 2, "scale": 1.0},
	{"pattern": "gtx\\s*16\\d\\d", "family": "nvidia_gtx16", "level": 2, "scale": 1.0},
	{"pattern": "gtx\\s*10(80|70|60)", "family": "nvidia_gtx10_high", "level": 2, "scale": 1.0},
	{"pattern": "gtx\\s*10\\d\\d", "family": "nvidia_gtx10_low", "level": 1, "scale": 1.0},
	{"pattern": "gtx\\s*9\\d\\d", "family": "nvidia_gtx9", "level": 1, "scale": 0.9},
	{"pattern": "(gt|gtx)\\s*\\d{3,4}", "family": "nvidia_legacy", "level": 0, "scale": 0.8},
	# AMD
	{"pattern": "rx\\s*(7[6-9]00|6[7-9]00|9[0-9]00)", "family": "amd_rx_high", "level": 3, "scale": 1.0},
	{"pattern": "rx\\s*(7[0-5]00|6[0-6]00)", "family": "amd_rx_mid", "level": 2, "scale": 1.0},
	{"pattern": "rx\\s*5[0-9]00", "family": "amd_rx5000", "level": 2, "scale": 1.0},
	{"pattern": "(rx\\s*[45]\\d\\d\\b|vega)", "family": "amd_polaris_vega", "level": 1, "scale": 0.9},
	{"pattern": "radeon.*graphics", "family": "amd_igpu", "level": 1, "scale": 0.8},
	# Intel
	{"pattern": "intel.*arc", "family": "intel_arc", "level": 2, "scale": 1.0},
	{"pattern": "iris.*(xe|plus)", "family": "intel_iris_xe", "level": 1, "scale": 0.85},
	{"pattern": "intel.*(uhd|hd graphics)", "family": "intel_uhd", "level": 0, "scale": 0.75},
	# Mobile
	{"pattern": "immortalis", "family": "mali_immortalis", "level": 2, "scale": 0.85},
	{"pattern": "mali-g7[1-9]\\d", "family": "mali_g7", "level": 1, "scale": 0.8},
	{"pattern": "mali", "family": "mali_low", "level": 0, "scale": 0.7},
	{"pattern": "adreno.*\\(?(7\\d\\d)", "family": "adreno_7xx", "level": 2, "scale": 0.85},
	{"pattern": "adreno.*\\(?6[4-9]\\d", "family": "adreno_64x", "level": 1, "scale": 0.8},
	{"pattern": "adreno", "family": "adreno_low", "level": 0, "scale": 0.7},
]

const VENDOR_FALLBACK: Dictionary = {
	"apple": 2, "nvidia": 2, "amd": 1, "ati": 1, "intel": 0, "qualcomm": 0, "arm": 0,
}


## Static recommendation, no learned data. Returns {level, scale, family, source, features}.
static func match_adapter(adapter: String, vendor: String = "") -> Dictionary:
	var name: String = adapter.to_lower()
	for rule in RULES:
		var re: RegEx = RegEx.new()
		if re.compile(str(rule["pattern"])) != OK:
			continue
		if re.search(name) != null:
			var level: int = int(rule["level"])
			return {"level": level, "scale": float(rule["scale"]), "family": str(rule["family"]),
				"source": "database", "features": features_for(level)}
	return _fallback(name, vendor.to_lower())


static func _fallback(name: String, vendor: String) -> Dictionary:
	var level: int = 1
	var scale: float = 0.9
	var hay: String = name + " " + vendor
	for key in VENDOR_FALLBACK.keys():
		if hay.contains(str(key)):
			level = int(VENDOR_FALLBACK[key])
			break
	if hay.contains("software") or hay.contains("llvmpipe") or hay.contains("swiftshader"):
		level = 0
		scale = 0.5
	return {"level": level, "scale": scale, "family": "unknown", "source": "fallback",
		"features": features_for(level)}


static func features_for(level: int) -> Dictionary:
	var lv: int = clampi(level, 0, MAX_LEVEL)
	return {
		"ssao": lv >= 2,
		"ssr": lv >= 3,
		"volumetric_fog": lv >= 2,
		"sdfgi": lv >= 3,
		"glow": lv >= 1,
		"shadow_quality": lv,
		"msaa": 0 if lv < 2 else (2 if lv == 2 else 4),
	}


## Full recommendation: learned data when present, otherwise the static database/heuristic.
static func recommend(adapter: String, vendor: String = "", target_ms: float = TARGET_FRAME_MS,
		path: String = DEFAULT_PATH) -> Dictionary:
	var base: Dictionary = match_adapter(adapter, vendor)
	var per_level: Dictionary = _medians(adapter, path)
	if per_level.is_empty():
		return base
	var best: int = -1
	var lowest_measured: int = MAX_LEVEL + 1
	for k in per_level.keys():
		var lv: int = int(k)
		lowest_measured = mini(lowest_measured, lv)
		if float(per_level[k]) <= target_ms and lv > best:
			best = lv
	var chosen: int
	if best >= 0:
		chosen = best
		if float(per_level[best]) < target_ms * 0.7 and not per_level.has(best + 1):
			chosen = mini(best + 1, MAX_LEVEL)
	else:
		chosen = maxi(lowest_measured - 1, 0)
	base["level"] = chosen
	base["source"] = "learned"
	base["features"] = features_for(chosen)
	return base


## Records a measured average frame time for this adapter at a quality level.
static func learn(adapter: String, measured_frame_ms: float, level: int, path: String = DEFAULT_PATH) -> bool:
	if measured_frame_ms <= 0.0:
		return false
	var data: Dictionary = _load(path)
	var key: String = adapter.strip_edges().to_lower()
	var entry: Dictionary = data.get(key, {})
	var lk: String = str(clampi(level, 0, MAX_LEVEL))
	var samples: Array = entry.get(lk, [])
	samples.append(measured_frame_ms)
	while samples.size() > MAX_SAMPLES_PER_LEVEL:
		samples.pop_front()
	entry[lk] = samples
	data[key] = entry
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


static func _medians(adapter: String, path: String) -> Dictionary:
	var out: Dictionary = {}
	var data: Dictionary = _load(path)
	var entry: Dictionary = data.get(adapter.strip_edges().to_lower(), {})
	for k in entry.keys():
		var samples: Array = entry[k]
		if samples.is_empty():
			continue
		var vals: PackedFloat32Array = PackedFloat32Array()
		for s in samples:
			vals.append(float(s))
		vals.sort()
		var n: int = vals.size()
		var med: float = vals[n / 2] if n % 2 == 1 else (vals[n / 2 - 1] + vals[n / 2]) * 0.5
		out[int(k)] = med
	return out


static func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		var d: Dictionary = parsed
		return d
	return {}


## Convenience for the running game: uses the live adapter.
static func recommend_current() -> Dictionary:
	return recommend(RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor())
