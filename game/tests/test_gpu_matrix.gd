extends RefCounted
## GPU compatibility matrix, regression detection, exports and input-latency statistics.

const MatrixDb = preload("res://scripts/tools/gpu_matrix_db.gd")
const GpuSettingsDb = preload("res://scripts/client/gpu_settings_db.gd")
const LatencyProbe = preload("res://scripts/client/input_latency_probe.gd")

const H_BASE: String = "0000000000000000"
const H_NEAR: String = "000000000000000f"
const H_FAR: String = "ffffffff00000000"


static func _run_entry(level: int, p50: float, hashes: Array[String], errors: int = 0) -> Dictionary:
	return {"level": level, "frames": 300, "frame_ms": {"avg": p50, "p50": p50, "p95": p50 * 1.3, "p99": p50 * 1.6, "max": p50 * 2.0},
		"gpu_ms": {"avg": p50 * 0.8}, "pipeline_compiles": 3, "checksums": hashes, "errors": errors}


static func _report(adapter: String, vendor: String, driver: String, renderer: String, runs: Array[Dictionary]) -> Dictionary:
	return {"schema": 1, "system": {"adapter": adapter, "vendor": vendor, "driver": driver, "os": "Windows",
		"os_version": "11", "renderer": renderer}, "runs": runs}


static func _good_runs(hash_value: String, p50: float) -> Array[Dictionary]:
	var hs: Array[String] = [hash_value, hash_value]
	var runs: Array[Dictionary] = []
	for lv in 4:
		runs.append(_run_entry(lv, p50 + float(lv) * 2.0, hs))
	return runs


func run(t) -> void:
	t.current = "report schema"
	var ok: Dictionary = _report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", _good_runs(H_BASE, 5.0))
	t.eq(MatrixDb.validate_report(ok).size(), 0, "valid report has no problems")
	t.check(MatrixDb.validate_report("nope").size() > 0, "non-object rejected")
	var bad_schema: Dictionary = ok.duplicate(true)
	bad_schema["schema"] = 9
	t.check(MatrixDb.validate_report(bad_schema).size() > 0, "unknown schema rejected")
	var no_sys: Dictionary = ok.duplicate(true)
	no_sys.erase("system")
	t.check(MatrixDb.validate_report(no_sys).size() > 0, "missing system rejected")
	var bad_hash: Dictionary = ok.duplicate(true)
	((bad_hash["runs"] as Array)[0] as Dictionary)["checksums"] = ["xyz"]
	t.check(MatrixDb.validate_report(bad_hash).size() > 0, "malformed checksum rejected")
	var bad_level: Dictionary = ok.duplicate(true)
	((bad_level["runs"] as Array)[0] as Dictionary)["level"] = 7
	t.check(MatrixDb.validate_report(bad_level).size() > 0, "level out of range rejected")
	var db0: RefCounted = MatrixDb.new()
	t.check(not db0.add_report(no_sys, "bad.json"), "add_report refuses invalid data")
	t.eq(db0.rejected.size(), 1, "rejection is recorded")
	t.check(db0.add_report(ok), "add_report accepts valid data")

	t.current = "perceptual hash"
	t.eq(MatrixDb.hash_distance(H_BASE, H_NEAR), 4, "popcount distance")
	t.eq(MatrixDb.hash_distance(H_BASE, H_FAR), 32, "wide distance")
	t.eq(MatrixDb.hash_distance(H_BASE, "abc"), -1, "malformed hash gives -1")
	var grad: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	var inv: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v: float = float(x) / 63.0
			grad.set_pixel(x, y, Color(v, v, v))
			inv.set_pixel(x, y, Color(1.0 - v, 1.0 - v, 1.0 - v))
	var hg: String = MatrixDb.dhash(grad)
	t.eq(hg.length(), 16, "dhash is 16 hex chars")
	t.eq(MatrixDb.hash_distance(hg, MatrixDb.dhash(grad)), 0, "same image hashes identically")
	t.check(MatrixDb.hash_distance(hg, MatrixDb.dhash(inv)) > 40, "inverted gradient is far away")
	t.eq(MatrixDb.dhash(Image.new()), "", "empty image gives empty hash")

	t.current = "matrix aggregation"
	var db: RefCounted = MatrixDb.new()
	db.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", _good_runs(H_BASE, 5.0)))
	db.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", _good_runs(H_NEAR, 7.0)))
	db.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", _good_runs(H_BASE, 6.0)))
	db.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "555.0", "vulkan", _good_runs(H_FAR, 5.0)))
	db.add_report(_report("AMD Radeon RX 7800 XT", "AMD", "24.1", "vulkan", _good_runs(H_BASE, 6.0)))
	var cells: Array[Dictionary] = db.cells()
	t.eq(cells.size(), 3, "three vendor/family/driver/renderer cells")
	var nv_ok: Dictionary = {}
	var nv_bad: Dictionary = {}
	for c in cells:
		if c["vendor"] == "nvidia" and c["driver"] == "560.1":
			nv_ok = c
		elif c["vendor"] == "nvidia" and c["driver"] == "555.0":
			nv_bad = c
	t.eq(nv_ok.get("reports", 0), 3, "three reports share the good NVIDIA cell")
	t.eq(nv_ok.get("status", ""), "pass", "near-identical frames pass within tolerance")
	t.eq(nv_ok.get("family", ""), "nvidia_rtx_high", "family comes from the settings database")
	t.near(float(((nv_ok.get("level_p50", {}) as Dictionary).get(0, 0.0))), 6.0, 0.001, "median p50 for level 0")
	t.eq(nv_ok.get("max_level_60fps", -9), 3, "all levels hit 60fps")
	t.eq(nv_bad.get("status", ""), "fail", "wrong output fails the bad driver cell")

	t.current = "regression detection"
	var regs: Array[Dictionary] = db.regressions()
	t.eq(regs.size(), 8, "4 levels x 2 frames flagged for the bad driver")
	t.eq(int(regs[0]["distance"]), 32, "distance recorded")
	db.tolerance = 40
	db.build()
	t.eq(db.regressions().size(), 0, "a looser tolerance accepts the same frames")
	db.tolerance = MatrixDb.DEFAULT_TOLERANCE
	db.set_reference("vulkan", 0, 0, H_FAR)
	db.build()
	t.check(db.regressions().size() > 0, "a pinned reference changes the verdict")

	t.current = "driver failure clustering"
	var db2: RefCounted = MatrixDb.new()
	for i in 3:
		db2.add_report(_report("NVIDIA GeForce RTX 3060", "NVIDIA", "560.1", "vulkan", _good_runs(H_BASE, 6.0)))
	var broken: Array[Dictionary] = _good_runs(H_BASE, 6.0)
	broken[2]["errors"] = 4
	db2.add_report(_report("NVIDIA GeForce RTX 3060", "NVIDIA", "555.0", "vulkan", broken))
	db2.add_report(_report("NVIDIA GeForce RTX 3070", "NVIDIA", "555.0", "vulkan", broken))
	var crash: Dictionary = _report("Intel Arc A750", "Intel", "31.0", "d3d12", _good_runs(H_BASE, 8.0))
	crash["completed"] = false
	db2.add_report(crash)
	var clusters: Array[Dictionary] = db2.driver_failures()
	t.eq(clusters.size(), 2, "bad NVIDIA driver and crashing Intel run")
	var nv_cluster: Dictionary = {}
	for c in clusters:
		if c["vendor"] == "nvidia":
			nv_cluster = c
	t.eq(nv_cluster.get("driver", ""), "555.0", "NVIDIA 555 clustered")
	t.eq(nv_cluster.get("fails", 0), 2, "both reports counted")
	t.eq(nv_cluster.get("families", []).size(), 2, "both affected families listed once")
	t.check(bool(nv_cluster.get("driver_specific", false)), "other NVIDIA driver passes so it is driver specific")
	t.check((nv_cluster.get("reasons", {}) as Dictionary).has("errors:L2"), "error reason recorded")
	var intel: Dictionary = {}
	for c in clusters:
		if c["vendor"] == "intel":
			intel = c
	t.check(not bool(intel.get("driver_specific", true)), "no comparison driver so not driver specific")
	t.check((intel.get("reasons", {}) as Dictionary).has("crash"), "crash reason recorded")

	t.current = "learned recommendations"
	var db3: RefCounted = MatrixDb.new()
	var rs3: Array[Dictionary] = []
	for lv in 4:
		var hs: Array[String] = [H_FAR if lv == 3 else H_BASE]
		rs3.append(_run_entry(lv, 4.0 + float(lv) * 3.0, hs))
	db3.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", rs3))
	db3.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", _good_runs(H_BASE, 4.0)))
	db3.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", _good_runs(H_BASE, 4.0)))
	var learned: Dictionary = db3.learned_data()
	t.check(learned.has("nvidia geforce rtx 4070"), "keyed by lowercase adapter")
	var entry: Dictionary = learned["nvidia geforce rtx 4070"]
	t.eq((entry["0"] as Array).size(), 3, "one sample per report and level")
	t.check(float(entry["3"][0]) == MatrixDb.BLOCKED_LEVEL_MS or float(entry["3"][1]) == MatrixDb.BLOCKED_LEVEL_MS
		or float(entry["3"][2]) == MatrixDb.BLOCKED_LEVEL_MS, "a visually wrong level is blocked")
	# Single outlier at level 3 does not move the median; verify the file feeds GpuSettingsDb.
	var path: String = "user://test_gpu_matrix_learned.json"
	t.check(db3.write_learned(path), "learned JSON written")
	var rec: Dictionary = GpuSettingsDb.recommend("NVIDIA GeForce RTX 4070", "NVIDIA", 16.6, path)
	t.eq(rec["source"], "learned", "settings DB reads the file")
	t.eq(rec["level"], 3, "median across reports still allows level 3 when one report is blocked")
	var db4: RefCounted = MatrixDb.new()
	db4.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", rs3))
	db4.add_report(_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", rs3))
	db4.write_learned(path)
	t.eq(GpuSettingsDb.recommend("NVIDIA GeForce RTX 4070", "NVIDIA", 16.6, path)["level"], 3,
		"identical frames form their own reference so nothing is blocked")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	t.current = "export formats"
	var md: String = db.to_markdown()
	t.check(md.contains("# GPU compatibility matrix"), "markdown title")
	t.check(md.contains("| nvidia | nvidia_rtx_high | 560.1 | vulkan |"), "markdown row")
	t.check(md.contains("## Rendering regressions"), "markdown regression section")
	var md2: String = db2.to_markdown()
	t.check(md2.contains("(driver-specific)"), "markdown flags driver specific failures")
	var csv: String = db.to_csv()
	var lines: PackedStringArray = csv.strip_edges().split("\n")
	t.eq(lines.size(), db.cells().size() + 1, "csv header plus one row per cell")
	t.check(lines[0].begins_with("vendor,family,driver,renderer"), "csv header")
	t.eq(lines[1].split(",").size() >= 15, true, "csv rows are full width")
	t.eq(MatrixDb._csv("a,b"), "\"a,b\"", "csv quotes commas")
	t.eq(MatrixDb._csv("say \"hi\""), "\"say \"\"hi\"\"\"", "csv escapes quotes")

	t.current = "latency statistics"
	var s: Array[Dictionary] = []
	for i in 5:
		s.append({"mode": "normal", "input_us": i * 100000, "draw_us": i * 100000 + 20000 + i * 1000, "photodiode_us": -1})
	for i in 5:
		s.append({"mode": "framegen", "input_us": 1000000 + i * 100000, "draw_us": 1000000 + i * 100000 + 30000, "photodiode_us": -1})
	s.append({"mode": "normal", "input_us": 9000000, "draw_us": -1, "photodiode_us": -1})
	var stats: Dictionary = LatencyProbe.summarize(s, 8.0)
	t.eq(stats.keys().size(), 2, "two modes reported, incomplete sample dropped")
	var n: Dictionary = stats["normal"]
	t.eq(n["count"], 5, "five complete normal samples")
	t.near(float(n["min"]), 28.0, 0.001, "min includes display estimate")
	t.near(float(n["p50"]), 30.0, 0.001, "median")
	t.near(float(n["max"]), 32.0, 0.001, "max")
	t.near(float(n["avg"]), 30.0, 0.001, "average")
	t.near(float(n["p95"]), 31.8, 0.001, "interpolated p95")
	t.eq(n["source"], "software", "software source")
	t.near(float((stats["framegen"] as Dictionary)["jitter"]), 0.0, 0.001, "constant latency has no jitter")
	t.near(float((stats["framegen"] as Dictionary)["p50"]) - float(n["p50"]), 8.0, 0.001, "mode delta visible")
	var sorted_vals: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0])
	t.near(LatencyProbe.percentile(sorted_vals, 50.0), 3.0, 0.0001, "percentile median")
	t.near(LatencyProbe.percentile(sorted_vals, 0.0), 1.0, 0.0001, "percentile 0")
	t.near(LatencyProbe.percentile(sorted_vals, 100.0), 5.0, 0.0001, "percentile 100")
	t.near(LatencyProbe.percentile(PackedFloat64Array(), 50.0), 0.0, 0.0001, "empty percentile")
	var edges: PackedInt64Array = PackedInt64Array([0 + 45000, 100000 + 52000, 4000000])
	var paired: int = LatencyProbe.pair_photodiode(s, edges, 0)
	t.eq(paired, 2, "edge far from any input stays unpaired")
	t.eq(s[0]["photodiode_us"], 45000, "first edge pairs with the first input")
	t.near(LatencyProbe.latency_ms(s[0], 8.0), 45.0, 0.001, "photodiode overrides the estimate")
	var stats2: Dictionary = LatencyProbe.summarize(s, 8.0)
	t.eq((stats2["normal"] as Dictionary)["source"], "mixed", "partially measured mode is mixed")
