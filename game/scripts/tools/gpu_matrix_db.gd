extends RefCounted
## GPU compatibility matrix and rendering-regression database.
## Ingests the JSON reports written by gpu_benchmark_run.gd (collected manually from testers),
## builds vendor x family x driver x renderer cells (pass / fail / perf), detects visual
## regressions by perceptual-hash distance against a per-renderer reference, clusters failures
## by driver, exports Markdown / CSV, and writes a learned JSON importable by
## scripts/client/gpu_settings_db.gd (same layout as user://gpu_learned.json).
##
## Concepts (not code) follow public practice: result-schema versioning as in 3DMark / Unity
## benchmark reports and the Steam hardware survey (adapter + driver + OS only, no personal data);
## the difference hash (dHash) is the public-domain "perceptual hash" idea (9x8 greyscale,
## 64 gradient bits). All code here is original (MIT-compatible).
##
## Typical use:
##   var db := preload("res://scripts/tools/gpu_matrix_db.gd").new()
##   db.ingest_dir("user://reports"); db.build()
##   print(db.to_markdown()); db.write_learned("user://gpu_learned.json")

const GpuSettingsDb = preload("res://scripts/client/gpu_settings_db.gd")

const SCHEMA_VERSION: int = 1
const HASH_HEX_LEN: int = 16
const DEFAULT_TOLERANCE: int = 8
## Frame time written into the learned JSON for a level that rendered incorrectly, so
## GpuSettingsDb.recommend() never picks it.
const BLOCKED_LEVEL_MS: float = 1000.0
const MAX_LEARNED_SAMPLES: int = 31
const POPCOUNT: Array[int] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]

## Maximum Hamming distance (of 64 bits) for two frames to count as the same image.
var tolerance: int = DEFAULT_TOLERANCE
var target_ms: float = GpuSettingsDb.TARGET_FRAME_MS
var reports: Array[Dictionary] = []
var rejected: Array[String] = []

var _manual_refs: Dictionary = {}
var _references: Dictionary = {}
var _evals: Array[Dictionary] = []
var _built: bool = false


# ------------------------------------------------------------------ schema

## Returns a list of problems; empty means the report is valid.
static func validate_report(rep: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (rep is Dictionary):
		errs.append("report is not an object")
		return errs
	var d: Dictionary = rep
	if int(d.get("schema", 0)) != SCHEMA_VERSION:
		errs.append("unsupported schema %s" % str(d.get("schema", "missing")))
	var sys_v: Variant = d.get("system", null)
	if not (sys_v is Dictionary):
		errs.append("missing system")
	else:
		var sys: Dictionary = sys_v
		for k in ["adapter", "vendor", "driver", "os", "renderer"]:
			if not (sys.get(k, null) is String) or str(sys[k]).strip_edges().is_empty():
				errs.append("system.%s missing" % k)
	var runs_v: Variant = d.get("runs", null)
	if not (runs_v is Array) or (runs_v as Array).is_empty():
		errs.append("runs missing or empty")
		return errs
	var runs: Array = runs_v
	for i in runs.size():
		var r_v: Variant = runs[i]
		if not (r_v is Dictionary):
			errs.append("runs[%d] is not an object" % i)
			continue
		var r: Dictionary = r_v
		var lv: int = int(r.get("level", -1))
		if lv < 0 or lv > GpuSettingsDb.MAX_LEVEL:
			errs.append("runs[%d].level out of range" % i)
		var fm_v: Variant = r.get("frame_ms", null)
		if not (fm_v is Dictionary):
			errs.append("runs[%d].frame_ms missing" % i)
		else:
			var fm: Dictionary = fm_v
			for k in ["p50", "p95", "p99"]:
				var v: Variant = fm.get(k, null)
				if not (v is int or v is float) or float(v) < 0.0:
					errs.append("runs[%d].frame_ms.%s invalid" % [i, k])
		if int(r.get("errors", 0)) < 0:
			errs.append("runs[%d].errors negative" % i)
		var cs_v: Variant = r.get("checksums", [])
		if not (cs_v is Array):
			errs.append("runs[%d].checksums not an array" % i)
		else:
			for c in (cs_v as Array):
				if not (c is String) or str(c).length() != HASH_HEX_LEN or not str(c).is_valid_hex_number():
					errs.append("runs[%d] bad checksum" % i)
					break
	return errs


# ------------------------------------------------------------------ perceptual hash

## 64-bit difference hash of an image as 16 hex chars ("" for an empty image).
static func dhash(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	var g: Image = img.duplicate()
	if g.is_compressed():
		g.decompress()
	g.convert(Image.FORMAT_L8)
	g.resize(9, 8, Image.INTERPOLATE_LANCZOS)
	var out: String = ""
	var nibble: int = 0
	var bits: int = 0
	for y in 8:
		for x in 8:
			var l: float = g.get_pixel(x, y).r
			var r: float = g.get_pixel(x + 1, y).r
			nibble = (nibble << 1) | (1 if l > r else 0)
			bits += 1
			if bits % 4 == 0:
				out += "%x" % nibble
				nibble = 0
	return out


## Hamming distance between two hashes; -1 when either is malformed.
static func hash_distance(a: String, b: String) -> int:
	if a.length() != HASH_HEX_LEN or b.length() != HASH_HEX_LEN:
		return -1
	if not a.is_valid_hex_number() or not b.is_valid_hex_number():
		return -1
	var dist: int = 0
	for i in HASH_HEX_LEN:
		var x: int = a.substr(i, 1).hex_to_int() ^ b.substr(i, 1).hex_to_int()
		dist += POPCOUNT[x]
	return dist


# ------------------------------------------------------------------ ingest

func add_report(rep: Variant, source: String = "") -> bool:
	var errs: Array[String] = validate_report(rep)
	if not errs.is_empty():
		rejected.append("%s: %s" % [source if not source.is_empty() else "report", "; ".join(errs)])
		return false
	var d: Dictionary = rep
	reports.append(d)
	_built = false
	return true


func ingest_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		rejected.append("%s: not found" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		rejected.append("%s: invalid JSON" % path)
		return false
	return add_report(parsed, path)


## Ingests every gpu_report_*.json in a directory; returns how many were accepted.
func ingest_dir(dir_path: String) -> int:
	var count: int = 0
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		rejected.append("%s: cannot open directory" % dir_path)
		return 0
	for f in dir.get_files():
		if f.begins_with("gpu_report_") and f.ends_with(".json"):
			if ingest_file(dir_path.path_join(f)):
				count += 1
	return count


## Pins a known-good hash for renderer/level/frame index (overrides the learned medoid).
func set_reference(renderer: String, level: int, index: int, checksum: String) -> void:
	_manual_refs[_ref_key(renderer, level, index)] = checksum
	_built = false


static func _ref_key(renderer: String, level: int, index: int) -> String:
	return "%s|%d|%d" % [renderer.to_lower(), level, index]


# ------------------------------------------------------------------ analysis

## Recomputes references and the per-report evaluations. Called lazily by the accessors.
func build() -> void:
	_references.clear()
	_evals.clear()
	var groups: Dictionary = {}
	for rep in reports:
		var sys: Dictionary = rep["system"]
		var renderer: String = str(sys["renderer"]).to_lower()
		for r_v in (rep["runs"] as Array):
			var r: Dictionary = r_v
			var cs: Array = r.get("checksums", [])
			for i in cs.size():
				var key: String = _ref_key(renderer, int(r["level"]), i)
				if not groups.has(key):
					groups[key] = []
				(groups[key] as Array).append(str(cs[i]))
	for key in groups.keys():
		_references[key] = _medoid(groups[key])
	for key in _manual_refs.keys():
		_references[key] = _manual_refs[key]
	for rep in reports:
		_evals.append(_evaluate(rep))
	_built = true


static func _medoid(hashes: Array) -> String:
	var best: String = ""
	var best_sum: int = 1 << 30
	for a in hashes:
		var total: int = 0
		for b in hashes:
			total += maxi(hash_distance(str(a), str(b)), 0)
		if total < best_sum:
			best_sum = total
			best = str(a)
	return best


func _evaluate(rep: Dictionary) -> Dictionary:
	var sys: Dictionary = rep["system"]
	var adapter: String = str(sys["adapter"])
	var vendor: String = str(sys["vendor"]).to_lower()
	var renderer: String = str(sys["renderer"]).to_lower()
	var family: String = str(GpuSettingsDb.match_adapter(adapter, vendor)["family"])
	var reasons: Array[String] = []
	var regressions: Array[Dictionary] = []
	var worst: int = 0
	var level_p50: Dictionary = {}
	var level_p95: Dictionary = {}
	var blocked: Dictionary = {}
	if rep.has("completed") and not bool(rep["completed"]):
		reasons.append("crash")
	for r_v in (rep["runs"] as Array):
		var r: Dictionary = r_v
		var lv: int = int(r["level"])
		var fm: Dictionary = r["frame_ms"]
		level_p50[lv] = float(fm["p50"])
		level_p95[lv] = float(fm["p95"])
		if int(r.get("errors", 0)) > 0:
			reasons.append("errors:L%d" % lv)
		var cs: Array = r.get("checksums", [])
		for i in cs.size():
			var ref: String = str(_references.get(_ref_key(renderer, lv, i), ""))
			var dist: int = hash_distance(str(cs[i]), ref)
			if dist > tolerance:
				regressions.append({"level": lv, "index": i, "distance": dist})
				blocked[lv] = true
				worst = maxi(worst, dist)
		if blocked.has(lv):
			reasons.append("regression:L%d" % lv)
	return {
		"adapter": adapter, "vendor": vendor, "family": family,
		"driver": str(sys["driver"]), "renderer": renderer,
		"status": "fail" if not reasons.is_empty() else "pass",
		"reasons": reasons, "regressions": regressions, "worst_distance": worst,
		"level_p50": level_p50, "level_p95": level_p95, "blocked": blocked,
	}


func evaluations() -> Array[Dictionary]:
	if not _built:
		build()
	return _evals


## Matrix cells keyed by vendor|family|driver|renderer, sorted by that key.
func cells() -> Array[Dictionary]:
	var map: Dictionary = {}
	for ev in evaluations():
		var key: String = "%s|%s|%s|%s" % [ev["vendor"], ev["family"], ev["driver"], ev["renderer"]]
		if not map.has(key):
			map[key] = {"vendor": ev["vendor"], "family": ev["family"], "driver": ev["driver"],
				"renderer": ev["renderer"], "reports": 0, "pass": 0, "fail": 0,
				"_samples": {}, "reasons": {}}
		var c: Dictionary = map[key]
		c["reports"] = int(c["reports"]) + 1
		c["pass" if ev["status"] == "pass" else "fail"] = int(c["pass" if ev["status"] == "pass" else "fail"]) + 1
		var samples: Dictionary = c["_samples"]
		var lp: Dictionary = ev["level_p50"]
		for lv in lp.keys():
			if not samples.has(lv):
				samples[lv] = []
			(samples[lv] as Array).append(float(lp[lv]))
		var rs: Dictionary = c["reasons"]
		for reason in (ev["reasons"] as Array):
			rs[reason] = int(rs.get(reason, 0)) + 1
	var out: Array[Dictionary] = []
	var keys: Array = map.keys()
	keys.sort()
	for key in keys:
		var c: Dictionary = map[key]
		var samples: Dictionary = c["_samples"]
		var p50: Dictionary = {}
		var best60: int = -1
		var lvls: Array = samples.keys()
		lvls.sort()
		for lv in lvls:
			var med: float = _median(samples[lv])
			p50[lv] = med
			if med <= target_ms:
				best60 = maxi(best60, int(lv))
		c.erase("_samples")
		c["level_p50"] = p50
		c["max_level_60fps"] = best60
		c["status"] = "fail" if int(c["fail"]) > 0 else "pass"
		c["perf"] = "ok" if best60 >= 0 else "slow"
		out.append(c)
	return out


static func _median(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var a: PackedFloat64Array = PackedFloat64Array()
	for v in vals:
		a.append(float(v))
	a.sort()
	var n: int = a.size()
	if n % 2 == 1:
		return a[n >> 1]
	return (a[(n >> 1) - 1] + a[n >> 1]) * 0.5


## Failures grouped by vendor + driver + renderer. "driver_specific" is true when the failure
## rate is at least 50% while another driver of the same vendor/renderer mostly passes.
func driver_failures() -> Array[Dictionary]:
	var map: Dictionary = {}
	for ev in evaluations():
		var key: String = "%s|%s|%s" % [ev["vendor"], ev["driver"], ev["renderer"]]
		if not map.has(key):
			map[key] = {"vendor": ev["vendor"], "driver": ev["driver"], "renderer": ev["renderer"],
				"total": 0, "fails": 0, "families": [], "reasons": {}}
		var c: Dictionary = map[key]
		c["total"] = int(c["total"]) + 1
		if ev["status"] == "fail":
			c["fails"] = int(c["fails"]) + 1
			var fams: Array = c["families"]
			if not fams.has(ev["family"]):
				fams.append(ev["family"])
			var rs: Dictionary = c["reasons"]
			for reason in (ev["reasons"] as Array):
				rs[reason] = int(rs.get(reason, 0)) + 1
	var out: Array[Dictionary] = []
	for key in map.keys():
		var c: Dictionary = map[key]
		var ratio: float = float(int(c["fails"])) / float(int(c["total"]))
		c["ratio"] = ratio
		var others_ok: bool = false
		for key2 in map.keys():
			if key2 == key:
				continue
			var o: Dictionary = map[key2]
			if o["vendor"] == c["vendor"] and o["renderer"] == c["renderer"] and o["driver"] != c["driver"]:
				if float(int(o["fails"])) / float(int(o["total"])) < 0.5:
					others_ok = true
		c["driver_specific"] = ratio >= 0.5 and others_ok
		if int(c["fails"]) > 0:
			out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ratio"] != b["ratio"]:
			return float(a["ratio"]) > float(b["ratio"])
		return str(a["driver"]) < str(b["driver"]))
	return out


## Every frame whose hash differs from the reference by more than the tolerance.
func regressions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev in evaluations():
		for rg in (ev["regressions"] as Array):
			var g: Dictionary = rg
			out.append({"adapter": ev["adapter"], "driver": ev["driver"], "renderer": ev["renderer"],
				"level": g["level"], "index": g["index"], "distance": g["distance"]})
	return out


# ------------------------------------------------------------------ recommendations

## {adapter_lower: {"level": [frame_ms...]}} in the user://gpu_learned.json layout.
## Levels that failed visually or errored are recorded as BLOCKED_LEVEL_MS.
func learned_data() -> Dictionary:
	var data: Dictionary = {}
	for ev in evaluations():
		var key: String = str(ev["adapter"]).strip_edges().to_lower()
		var entry: Dictionary = data.get(key, {})
		var lp: Dictionary = ev["level_p50"]
		var blocked: Dictionary = ev["blocked"]
		for lv in lp.keys():
			var lk: String = str(int(lv))
			var samples: Array = entry.get(lk, [])
			var ms: float = BLOCKED_LEVEL_MS if blocked.has(lv) else float(lp[lv])
			samples.append(ms)
			while samples.size() > MAX_LEARNED_SAMPLES:
				samples.pop_front()
			entry[lk] = samples
		data[key] = entry
	return data


func write_learned(path: String = GpuSettingsDb.DEFAULT_PATH) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(learned_data()))
	f.close()
	return true


# ------------------------------------------------------------------ export

func to_csv() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("vendor,family,driver,renderer,reports,pass,fail,status,perf,max_level_60fps,p50_L0,p50_L1,p50_L2,p50_L3,reasons")
	for c in cells():
		var p50: Dictionary = c["level_p50"]
		var cols: PackedStringArray = PackedStringArray([
			_csv(str(c["vendor"])), _csv(str(c["family"])), _csv(str(c["driver"])), _csv(str(c["renderer"])),
			str(c["reports"]), str(c["pass"]), str(c["fail"]), str(c["status"]), str(c["perf"]),
			str(c["max_level_60fps"])])
		for lv in 4:
			cols.append("%.2f" % float(p50[lv]) if p50.has(lv) else "")
		var rs: Array[String] = []
		var rd: Dictionary = c["reasons"]
		for k in rd.keys():
			rs.append("%s x%d" % [k, int(rd[k])])
		cols.append(_csv(" ".join(rs)))
		lines.append(",".join(cols))
	return "\n".join(lines) + "\n"


static func _csv(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s


static func _md(s: String) -> String:
	return s.replace("|", "\\|")


func to_markdown() -> String:
	var out: PackedStringArray = PackedStringArray()
	out.append("# GPU compatibility matrix")
	out.append("")
	out.append("Reports: %d accepted, %d rejected. Visual tolerance: %d/64 bits." % [reports.size(), rejected.size(), tolerance])
	out.append("")
	out.append("| Vendor | Family | Driver | Renderer | Reports | Pass | Fail | Perf | 60fps level | p50 L0 | L1 | L2 | L3 |")
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for c in cells():
		var p50: Dictionary = c["level_p50"]
		var row: PackedStringArray = PackedStringArray([
			_md(str(c["vendor"])), _md(str(c["family"])), _md(str(c["driver"])), _md(str(c["renderer"])),
			str(c["reports"]), str(c["pass"]), str(c["fail"]), str(c["perf"]), str(c["max_level_60fps"])])
		for lv in 4:
			row.append("%.1f" % float(p50[lv]) if p50.has(lv) else "-")
		out.append("| " + " | ".join(row) + " |")
	var drv: Array[Dictionary] = driver_failures()
	out.append("")
	out.append("## Driver failures")
	out.append("")
	if drv.is_empty():
		out.append("None.")
	for d in drv:
		var rs: Array[String] = []
		var rd: Dictionary = d["reasons"]
		for k in rd.keys():
			rs.append("%s x%d" % [k, int(rd[k])])
		out.append("- %s driver %s (%s): %d/%d failed%s - %s" % [d["vendor"], d["driver"], d["renderer"],
			d["fails"], d["total"], " (driver-specific)" if d["driver_specific"] else "", ", ".join(rs)])
	out.append("")
	out.append("## Rendering regressions")
	out.append("")
	var regs: Array[Dictionary] = regressions()
	if regs.is_empty():
		out.append("None.")
	for g in regs:
		out.append("- %s / %s / %s: level %d frame %d, distance %d" % [g["adapter"], g["driver"],
			g["renderer"], g["level"], g["index"], g["distance"]])
	if not rejected.is_empty():
		out.append("")
		out.append("## Rejected reports")
		out.append("")
		for r in rejected:
			out.append("- " + _md(r))
	return "\n".join(out) + "\n"
