extends RefCounted
## Trace capture, Chrome JSON export, frame stats, regression compare and hitch correlation.

const TraceCapture = preload("res://scripts/shared/trace_capture.gd")
const HitchCorrelator = preload("res://scripts/shared/hitch_correlator.gd")


func _events(tr) -> Array:
	var parsed: Variant = JSON.parse_string(tr.export_chrome_json())
	if parsed is Dictionary and parsed.has("traceEvents"):
		return parsed["traceEvents"]
	return []


func _count_ph(events: Array, ph: String) -> int:
	var n := 0
	for ev: Dictionary in events:
		if ev["ph"] == ph:
			n += 1
	return n


func _work(tr, id: int) -> void:
	tr.begin("worker_scope", "job")
	OS.delay_msec(10)
	tr.flow_end(id, "task")
	tr.end()


func run(t) -> void:
	t.current = "trace disabled"
	var off := TraceCapture.new()
	off.begin("x")
	off.end()
	off.counter("c", 1.0)
	off.instant("i")
	off.frame_marker(1)
	t.eq(off.event_count(), 0, "disabled capture records nothing")
	t.eq(off.measure("m", func(): return 5), 5, "measure still returns result when disabled")

	t.current = "trace nesting and export"
	var tr := TraceCapture.new()
	tr.enabled = true
	tr.begin("outer")
	tr.begin("inner", "physics")
	OS.delay_usec(200)
	tr.end()
	tr.end()
	tr.end()  # extra end is ignored
	t.eq(tr.event_count(), 2, "two scopes recorded, stray end ignored")
	tr.counter("entities", 42.0)
	tr.instant("spawn", {"kind": "zombie"})
	tr.flow_start(7, "task")
	tr.flow_end(7, "task")
	var parsed: Variant = JSON.parse_string(tr.export_chrome_json())
	t.check(parsed is Dictionary and parsed.has("traceEvents"), "JSON parses with traceEvents")
	var events := _events(tr)
	t.eq(_count_ph(events, "X"), 2, "complete events for scopes")
	t.eq(_count_ph(events, "C"), 1, "counter event")
	t.eq(_count_ph(events, "i"), 1, "instant event")
	t.eq(_count_ph(events, "s"), 1, "flow start")
	t.eq(_count_ph(events, "f"), 1, "flow end")
	t.check(_count_ph(events, "M") >= 2, "thread_name and process_name metadata")
	var outer: Dictionary = {}
	var inner: Dictionary = {}
	var last_ts: Dictionary = {}
	var monotonic := true
	for ev: Dictionary in events:
		if ev["ph"] == "M":
			continue
		if ev["name"] == "outer":
			outer = ev
		elif ev["name"] == "inner":
			inner = ev
		var tid: String = str(ev["tid"])
		if last_ts.has(tid) and float(ev["ts"]) < float(last_ts[tid]):
			monotonic = false
		last_ts[tid] = ev["ts"]
	t.check(monotonic, "ts is monotonic per thread")
	t.check(not outer.is_empty() and not inner.is_empty(), "both scopes exported")
	t.check(float(outer["ts"]) <= float(inner["ts"]), "outer starts before inner")
	t.check(float(outer["ts"]) + float(outer["dur"]) >= float(inner["ts"]) + float(inner["dur"]), "outer encloses inner")
	t.eq(inner["cat"], "physics", "category kept")
	t.check(tr.measure("calc", func(): return 6 * 7) == 42, "measure returns callable result")

	t.current = "trace ring buffer"
	var ring := TraceCapture.new()
	ring.enabled = true
	ring.max_events = 10
	for i in 50:
		ring.instant("e%d" % i)
	t.eq(ring.event_count(), 10, "ring buffer bounded by max_events")
	var ring_events := _events(ring)
	var names: Array = []
	for ev: Dictionary in ring_events:
		if ev["ph"] == "i":
			names.append(ev["name"])
	t.eq(names.size(), 10, "ten instants exported")
	t.eq(names[0], "e40", "oldest surviving event is first")
	t.eq(names[9], "e49", "newest event is last")

	t.current = "trace worker threads"
	var wt := TraceCapture.new()
	wt.enabled = true
	wt.set_thread_name("main-test")
	wt.flow_start(1, "task")
	var group := WorkerThreadPool.add_group_task(func(i: int) -> void: _work(wt, 1 + i), 4)
	WorkerThreadPool.wait_for_group_task_completion(group)
	var wev := _events(wt)
	var main_tid: int = OS.get_thread_caller_id()
	var worker_tids: Dictionary = {}
	var worker_scopes := 0
	for ev: Dictionary in wev:
		if ev["ph"] == "X" and ev["name"] == "worker_scope":
			worker_scopes += 1
			worker_tids[int(ev["tid"])] = true
	t.eq(worker_scopes, 4, "four worker scopes recorded")
	t.check(not worker_tids.has(main_tid), "worker scopes carry worker tids, not the main tid")
	t.check(worker_tids.size() >= 1, "at least one worker tid")
	var named := 0
	for ev: Dictionary in wev:
		if ev["ph"] == "M" and ev["name"] == "thread_name":
			named += 1
	t.check(named >= 2, "main and worker threads get thread_name metadata")
	t.eq(_count_ph(wev, "f"), 4, "flow ends recorded from workers")

	t.current = "trace frame stats"
	var fs := TraceCapture.new()
	fs.enabled = true
	fs.frame_marker(0)
	for f in 3:
		fs.begin("work")
		OS.delay_usec(1000)
		fs.end()
		fs.counter("n", float(f))
		fs.frame_marker(f + 1)
	var stats: Dictionary = fs.frame_stats()
	t.eq(stats["frames"], 3, "three frames captured")
	var work: Dictionary = stats["scopes"]["work"]
	t.check(float(work["total"]) >= 3000.0, "total covers three 1ms scopes")
	t.near(float(work["avg"]), float(work["total"]) / 3.0, 0.001, "avg is total over frames")
	t.check(float(work["max"]) >= float(work["avg"]), "max >= avg")
	t.eq(fs.frames().size(), 3, "frames() exposes per-frame records")

	t.current = "trace compare"
	var base := {"frames": 10, "scopes": {"a": {"total": 10000.0, "avg": 1000.0, "max": 1200.0}, "b": {"total": 10000.0, "avg": 1000.0, "max": 1200.0}}}
	var cur := {"frames": 10, "scopes": {"a": {"total": 13000.0, "avg": 1300.0, "max": 1500.0}, "b": {"total": 10500.0, "avg": 1050.0, "max": 1300.0}, "new": {"total": 1.0, "avg": 1.0, "max": 1.0}}}
	var report: Array = TraceCapture.compare(base, cur, 10.0)
	t.eq(report.size(), 1, "only the 30% regression is flagged")
	t.eq(report[0]["scope"], "a", "regressed scope named")
	t.near(float(report[0]["pct"]), 30.0, 0.01, "regression percentage")
	t.eq(TraceCapture.compare(base, base, 10.0).size(), 0, "identical stats do not regress")

	t.current = "trace stats json"
	var path := "user://test_trace_stats.json"
	t.check(fs.save_stats_json(path), "stats saved")
	var loaded: Dictionary = TraceCapture.load_stats_json(path)
	t.eq(int(loaded["frames"]), 3, "frames round trip")
	t.near(float(loaded["scopes"]["work"]["total"]), float(work["total"]), 0.001, "scope total round trip")
	t.check(fs.save("user://test_trace.json"), "chrome trace saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_trace.json"))
	t.check(TraceCapture.load_stats_json(path).is_empty(), "missing stats file yields empty dict")

	t.current = "hitch correlator"
	var frames: Array = []
	for i in 40:
		var ai := 2000.0
		var ms := 16.0
		var entities := 100.0
		if i == 30:
			ai = 20000.0
			ms = 40.0
			entities = 400.0
		frames.append({"ms": ms, "scopes": {"physics": 4000.0, "render": 8000.0, "ai": ai}, "counters": {"entities": entities, "draw": 50.0}})
	var hitches: Array = HitchCorrelator.correlate(frames, 25.0)
	t.eq(hitches.size(), 1, "one hitch frame")
	t.eq(hitches[0]["index"], 30, "hitch at frame 30")
	var culprits: Array = hitches[0]["culprits"]
	t.eq(culprits[0]["scope"], "ai", "guilty scope named first")
	t.near(float(culprits[0]["growth_usec"]), 18000.0, 0.01, "growth vs median")
	t.check(culprits.size() <= 3, "at most three culprits")
	var jumped: Array = hitches[0]["counters"]
	t.eq(jumped.size(), 1, "only the jumping counter reported")
	t.eq(jumped[0]["name"], "entities", "entities counter jumped")
	t.eq(HitchCorrelator.correlate(frames, 100.0).size(), 0, "no hitches above a high threshold")
