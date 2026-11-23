extends RefCounted
## Virtual shadow page manager, perf regression compare and readiness report.

const VSP = preload("res://scripts/shared/virtual_shadow_pages.gd")
const PerfRegression = preload("res://scripts/tools/perf_regression.gd")
const Readiness = preload("res://scripts/tools/production_readiness.gd")

const LIGHT := Vector3(0.0, -1.0, 0.0)


func _make(pool: int) -> RefCounted:
	var v: RefCounted = VSP.new()
	# 4 levels, 64m level 0, 128px pages, 1024 virtual -> 8x8 pages per level.
	v.setup(4, 64.0, 128, 1024, pool)
	return v


func _scene() -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	for i in 12:
		pts.append(Vector3(float(i) * 3.0 - 16.0, 0.0, float(i % 4) * 4.0 - 6.0))
	return pts


func _fp(n: int, value: float) -> PackedFloat32Array:
	var a: PackedFloat32Array = PackedFloat32Array()
	for i in n:
		a.append(value)
	return a


func run(t) -> void:
	t.current = "page level selection"
	var v: RefCounted = _make(256)
	v.begin_frame(LIGHT, Vector3.ZERO)
	t.eq(v.level_for_footprint(0.01), 0, "tiny footprint uses finest level")
	t.check(v.level_for_footprint(0.5) > 0, "larger footprint uses coarser level")
	t.eq(v.level_for_footprint(1000.0), 3, "huge footprint clamps to coarsest")
	var pts: PackedVector3Array = _scene()
	v.request_for_receivers(pts, _fp(pts.size(), 0.01))
	var fine: Dictionary = v.end_frame()
	var v2: RefCounted = _make(256)
	v2.begin_frame(LIGHT, Vector3.ZERO)
	v2.request_for_receivers(pts, _fp(pts.size(), 0.5))
	var coarse: Dictionary = v2.end_frame()
	t.check(int(fine["allocated"]) > int(coarse["allocated"]), "fine footprints need more pages than coarse")
	t.eq(int(fine["reused"]), 0, "first frame reuses nothing")
	t.eq(int(fine["rendered"]), int(fine["allocated"]), "new pages are rendered")

	t.current = "page cache reuse"
	var s: RefCounted = _make(256)
	s.begin_frame(LIGHT, Vector3.ZERO)
	s.request_for_receivers(pts, _fp(pts.size(), 0.02))
	var f1: Dictionary = s.end_frame()
	s.begin_frame(LIGHT, Vector3.ZERO)
	s.request_for_receivers(pts, _fp(pts.size(), 0.02))
	var f2: Dictionary = s.end_frame()
	t.eq(int(f2["rendered"]), 0, "static scene renders nothing on frame 2")
	t.eq(int(f2["reused"]), int(f1["allocated"]), "static scene reuses all pages")
	var table: PackedInt32Array = s.page_table()
	var mapped: int = 0
	for e in table:
		if e >= 0:
			mapped += 1
	t.eq(mapped, s.resident_count(), "page table maps every resident page")

	t.current = "caster invalidation"
	s.begin_frame(LIGHT, Vector3.ZERO)
	s.request_for_receivers(pts, _fp(pts.size(), 0.02))
	s.invalidate_casters([AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))])
	var f3: Dictionary = s.end_frame()
	t.check(int(f3["rendered"]) > 0, "moving caster dirties overlapping pages")
	t.check(int(f3["rendered"]) < int(f3["requested"]), "far pages stay cached")
	t.eq(int(f3["rendered"]) + int(f3["reused"]), int(f3["requested"]), "every request is rendered or reused")
	s.begin_frame(LIGHT, Vector3.ZERO)
	s.request_for_receivers(pts, _fp(pts.size(), 0.02))
	t.eq(int(s.end_frame()["rendered"]), 0, "pages are clean after re-render")

	t.current = "clipmap recentring"
	var r: RefCounted = _make(256)
	r.begin_frame(LIGHT, Vector3.ZERO)
	r.request_for_receivers(pts, _fp(pts.size(), 0.02))
	var g1: Dictionary = r.end_frame()
	var shift: float = r.page_world_size(0) * 2.0
	r.begin_frame(LIGHT, Vector3(shift + 0.01, 0.0, 0.0))
	r.request_for_receivers(pts, _fp(pts.size(), 0.02))
	var g2: Dictionary = r.end_frame()
	t.check(int(g2["reused"]) > 0, "recentring preserves cached pages")
	t.eq(int(g2["rendered"]), int(g2["allocated"]), "only newly exposed pages render")
	t.check(int(g2["reused"]) <= int(g1["allocated"]), "reuse never exceeds prior pages")
	t.eq(r.clipmap_center(0).x, 2, "centre snaps to whole pages")

	t.current = "LRU eviction"
	var p: RefCounted = _make(6)
	p.begin_frame(LIGHT, Vector3.ZERO)
	var line_a: PackedVector3Array = PackedVector3Array()
	var line_b: PackedVector3Array = PackedVector3Array()
	for i in 6:
		line_a.append(Vector3(float(i) * 8.0 - 15.0, 0.0, 1.0))
		line_b.append(Vector3(float(i) * 8.0 - 15.0, 0.0, 20.0))
	p.request_for_receivers(line_a, _fp(6, 0.01))
	var h1: Dictionary = p.end_frame()
	t.eq(int(h1["resident"]), 6, "pool fills to capacity")
	p.begin_frame(LIGHT, Vector3.ZERO)
	p.request_for_receivers(line_b, _fp(6, 0.01))
	var h2: Dictionary = p.end_frame()
	t.eq(int(h2["evicted"]), int(h2["allocated"]), "full pool evicts one page per new page")
	t.check(int(h2["resident"]) <= 6, "resident never exceeds pool")
	t.check(int(h2["allocated"]) > 0, "new pages allocated under pressure")


	t.current = "renderer-ready shadow page jobs and toroidal window safety"
	var gpu_pages: RefCounted = VSP.new()
	gpu_pages.setup(1, 64.0, 128, 512, 8) # 4x4 pages.
	gpu_pages.begin_frame(LIGHT, Vector3.ZERO)
	var single := PackedVector3Array([Vector3.ZERO])
	gpu_pages.request_for_receivers(single, _fp(1, 0.01))
	t.eq(int(gpu_pages.end_frame()["rendered"]), 1,
		"visible centre page is requested for rendering")
	var initial_jobs: PackedInt32Array = gpu_pages.get_render_jobs()
	t.eq(initial_jobs.size(), 4, "one page has a 4-int GPU render record")
	if initial_jobs.size() == 4:
		t.eq(initial_jobs[0], 0, "render job carries clipmap level")
		t.eq(initial_jobs[1], 0, "render job carries global X coordinate")
		t.eq(initial_jobs[2], 0, "render job carries global Y coordinate")
		t.eq(gpu_pages.page_table()[0], initial_jobs[3],
			"render target slot agrees with the current page table")
	var step: float = gpu_pages.page_world_size(0) * 4.0
	gpu_pages.begin_frame(LIGHT, Vector3(step, 0, 0))
	t.eq(gpu_pages.get_render_jobs().size(), 0,
		"new frame clears previous renderer commands")
	single[0] = Vector3(step, 0, 0)
	gpu_pages.request_for_receivers(single, _fp(1, 0.01))
	gpu_pages.end_frame()
	var moved_jobs: PackedInt32Array = gpu_pages.get_render_jobs()
	t.eq(moved_jobs.size(), 4, "new clipmap region schedules exactly one new page")
	if moved_jobs.size() == 4:
		t.eq(moved_jobs[1], 4, "new page keeps unwrapped global page X")
		t.eq(gpu_pages.page_table()[0], moved_jobs[3],
			"old resident page never aliases a new clipmap table slot")
	t.eq(gpu_pages.resident_count(), 2, "old page is still cached for returning")
	gpu_pages.begin_frame(LIGHT, Vector3(step, 0, 0))
	gpu_pages.request_for_receivers(single, _fp(1, 0.01))
	gpu_pages.end_frame()
	t.eq(gpu_pages.get_render_jobs().size(), 0, "unchanged static pages need no GPU work")
	gpu_pages.setup(1, 16.0, 128, 128, 1)
	gpu_pages.begin_frame(LIGHT, Vector3.ZERO)
	single[0] = Vector3.ZERO
	gpu_pages.request_for_receivers(single, _fp(1, 0.01))
	t.eq(int(gpu_pages.end_frame()["allocated"]), 1,
		"one-page VSM clipmap can request its centre")
	gpu_pages.setup(1, 48.0, 128, 384, 9)
	gpu_pages.begin_frame(LIGHT, Vector3.ZERO)
	var page_m: float = gpu_pages.page_world_size(0)
	gpu_pages.request_for_receivers(PackedVector3Array([
		Vector3(-page_m, 0, 0), Vector3.ZERO, Vector3(page_m, 0, 0)
	]), _fp(3, 0.01))
	t.eq(int(gpu_pages.end_frame()["allocated"]), 3,
		"odd-sized clipmap keeps all three columns of virtual pages")

	t.current = "perf regression"
	var base: Dictionary = {"frame_time_p50": 10.0, "frame_time_p95": 16.0, "frame_time_p99": 20.0,
		"memory_peak": 500.0, "draw_calls": 1000.0, "shader_compiles": 0.0}
	var bad: Dictionary = base.duplicate()
	bad["frame_time_p95"] = 19.2
	var ok2: Dictionary = base.duplicate()
	ok2["frame_time_p95"] = 16.32
	var th: Dictionary = {"default": 10.0}
	var rep_bad: Dictionary = PerfRegression.compare_runs(base, bad, th)
	var rep_ok: Dictionary = PerfRegression.compare_runs(base, ok2, th)
	t.check(not bool(rep_bad["ok"]), "20% p95 regression flagged")
	t.check((rep_bad["regressions"] as Array).has("frame_time_p95"), "p95 listed as regression")
	t.check(bool(rep_ok["ok"]), "2% p95 change tolerated")
	var noisy_b: Dictionary = {"runs": [{"frame_time_p95": 16.0}, {"frame_time_p95": 16.2}, {"frame_time_p95": 40.0}]}
	var noisy_c: Dictionary = {"runs": [{"frame_time_p95": 16.1}, {"frame_time_p95": 16.3}, {"frame_time_p95": 16.2}]}
	var rep_n: Dictionary = PerfRegression.compare_runs(noisy_b, noisy_c, th)
	t.check(bool(rep_n["ok"]), "median-of-runs ignores an outlier run")
	var sc: Dictionary = base.duplicate()
	sc["shader_compiles"] = 3.0
	t.check(not bool(PerfRegression.compare_runs(base, sc, th)["ok"]), "new shader compiles from zero flagged")
	var path: String = "user://perf_gate_test.json"
	t.check(PerfRegression.save_json(path, base), "save_json writes")
	t.eq(float(PerfRegression.load_json(path).get("draw_calls", 0.0)), 1000.0, "json round trip")
	t.eq(PerfRegression.load_json("user://missing_perf.json").size(), 0, "missing file loads empty")

	t.current = "leak trend"
	var leaky: PackedFloat32Array = PackedFloat32Array()
	var flat: PackedFloat32Array = PackedFloat32Array()
	for i in 60:
		leaky.append(500.0 + float(i) * 2.0 + float(i % 3))
		flat.append(500.0 + float(i % 5))
	var lt: Dictionary = PerfRegression.memory_leak_trend(leaky)
	t.check(bool(lt["leak"]), "steady growth is a leak")
	t.near(float(lt["slope"]), 2.0, 0.1, "slope recovered")
	t.check(not bool(PerfRegression.memory_leak_trend(flat)["leak"]), "noisy flat memory is not a leak")

	t.current = "log parser and report"
	var log_text: String = "test_x.gd    31 checks    0 failed\ntest_y.gd    10 checks    2 failed\nFAIL some check message\nSCRIPT ERROR: Parse Error: res://tests/test_z.gd:4\nTOTAL 41 checks, 2 failures\n"
	var parsed: Dictionary = Readiness.parse_test_log(log_text)
	var suites: Dictionary = parsed["suites"]
	t.eq(suites.size(), 3, "three suites parsed")
	t.eq(int((suites["test_x"] as Dictionary)["checks"]), 31, "check count parsed")
	t.eq(int((suites["test_y"] as Dictionary)["failed"]), 2, "failed count parsed")
	t.eq(((suites["test_y"] as Dictionary)["failures"] as Array).size(), 1, "FAIL line attached to suite")
	t.check(bool((suites["test_z"] as Dictionary)["unloadable"]), "script error marks suite unloadable")
	t.eq(int(parsed["total_failures"]), 2, "TOTAL parsed")
	var md_bad: String = Readiness.report(parsed, rep_bad, {"smoke": true})
	t.check(md_bad.contains("NO-GO"), "failures give NO-GO")
	t.check(md_bad.contains("test_y") and md_bad.contains("test_z"), "report names failing and unloadable suites")
	t.check(md_bad.contains("frame_time_p95"), "report lists perf regression")
	var clean: Dictionary = Readiness.parse_test_log("test_x.gd    31 checks    0 failed\nTOTAL 31 checks, 0 failures\n")
	var md_ok: String = Readiness.report(clean, rep_ok, {"smoke": {"pass": true, "detail": "ok"}})
	t.check(md_ok.contains("Verdict: GO"), "clean run gives GO")
	var rep_leak: Dictionary = rep_ok.duplicate()
	rep_leak["leak"] = lt
	t.check(Readiness.report(clean, rep_leak, {}).contains("NO-GO"), "leak gives NO-GO")
	t.check(Readiness.report(clean, rep_ok, {"smoke": false}).contains("NO-GO"), "failed extra gate gives NO-GO")
