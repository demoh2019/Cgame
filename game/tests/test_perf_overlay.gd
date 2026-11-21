extends RefCounted
## Performance overlay: ring buffers, percentiles, custom sources, hitch markers, modes, snapshot.

const PerfOverlay = preload("res://scripts/client/perf_overlay.gd")

var _counter: int = 0


func _next() -> float:
	_counter += 1
	return float(_counter)


func run(t) -> void:
	t.current = "ring buffer"
	var st := PerfOverlay.PerfStats.new(5)
	for i in 8:
		st.push("a", float(i))
	var s := st.series("a")
	t.eq(s.size(), 5, "ring never exceeds capacity")
	t.eq(s[0], 3.0, "oldest kept is 3")
	t.eq(s[4], 7.0, "newest is last")
	t.eq(st.series("missing").size(), 0, "unknown series is empty")
	st.push("a", NAN)
	t.eq(st.count("a"), 5, "non-finite ignored")
	t.eq(st.series("a", 2).size(), 2, "window limits series")

	t.current = "percentiles"
	var p := PerfOverlay.PerfStats.new(200)
	for i in 101:
		p.push("x", float(i))
	t.near(p.percentile("x", 50.0), 50.0, 0.001, "p50")
	t.near(p.percentile("x", 95.0), 95.0, 0.001, "p95")
	t.near(p.percentile("x", 99.0), 99.0, 0.001, "p99")
	t.near(p.percentile("x", 0.0), 0.0, 0.001, "p0 is min")
	t.near(p.percentile("x", 100.0), 100.0, 0.001, "p100 is max")
	t.near(p.percentile("x", 50.0, 11), 95.0, 0.001, "windowed median of last 11")
	t.eq(p.percentile("none", 50.0), 0.0, "empty percentile is zero")
	t.near(p.average("x"), 50.0, 0.001, "average")

	t.current = "overlay sampling"
	var ov: Node = PerfOverlay.new()
	t.eq(ov.mode, PerfOverlay.Mode.COMPACT, "starts compact")
	t.check(not ov.visible, "starts hidden")
	ov.add_source("queue", func() -> float: return _next())
	for i in 40:
		ov.call("_process", 0.016)
	t.eq(ov.stats.count("queue"), 40, "custom source sampled each frame")
	t.eq(ov.stats.last("queue"), 40.0, "custom source value")
	t.eq(ov.stats.count("frame_ms"), 40, "frame time sampled")
	t.near(ov.stats.last("frame_ms"), 16.0, 0.01, "frame ms from delta")
	t.check(ov.stats.has_series("mem_static_mb"), "memory sampled")
	t.check(ov.stats.has_series("pipelines"), "pipeline compilations sampled")
	ov.call("_process", -1.0)
	t.eq(ov.stats.count("frame_ms"), 40, "bad delta ignored")
	ov.remove_source("queue")
	ov.call("_process", 0.016)
	t.eq(ov.stats.count("queue"), 40, "removed source not sampled")

	t.current = "hitch markers"
	ov.call("_process", 0.3)
	t.check(ov.hitch_markers.size() >= 1, "slow frame recorded as hitch")
	if not ov.hitch_markers.is_empty():
		var m: Dictionary = ov.hitch_markers[ov.hitch_markers.size() - 1]
		t.eq(String(m["cause"]), "cpu", "cause labelled")
		t.near(float(m["ms"]), 300.0, 0.5, "hitch ms")
	ov.record_hitch({"ms": 80.0, "cause": "streaming", "time": 1.0})
	t.eq(String(ov.hitch_markers.back()["cause"]), "streaming", "external hitch accepted")
	for i in 50:
		ov.record_hitch({"ms": 60.0, "cause": "vram"})
	t.check(ov.hitch_markers.size() <= PerfOverlay.MAX_MARKERS, "markers bounded")

	t.current = "modes"
	t.eq(ov.cycle_mode(), PerfOverlay.Mode.FULL, "compact -> full")
	t.eq(ov.cycle_mode(), PerfOverlay.Mode.GRAPHS, "full -> graphs")
	t.eq(ov.cycle_mode(), PerfOverlay.Mode.COMPACT, "graphs -> compact")
	t.eq(ov.mode_name(), "compact", "mode name")
	ov.toggle()
	t.check(ov.visible, "toggle shows")
	ov.toggle()
	t.check(not ov.visible, "toggle hides")

	t.current = "snapshot"
	var snap: Dictionary = ov.snapshot()
	t.check(snap.has("stats") and snap.has("hitches") and snap.has("mode"), "snapshot keys")
	var sd: Dictionary = snap["stats"]
	t.check(sd.has("frame_ms") and sd.has("vram_mb"), "snapshot has series stats")
	var fm: Dictionary = sd["frame_ms"]
	t.check(fm.has("p50") and fm.has("p95") and fm.has("p99"), "snapshot has percentiles")
	t.check(int(snap["frame_index"]) > 40, "snapshot frame index")
	t.check(JSON.stringify(snap).length() > 10, "snapshot is JSON-serialisable")

	t.current = "overlay in tree"
	ov.free()
	var ov2: Node = PerfOverlay.new()
	ov2.call("_ready")
	ov2.call("_process", 0.016)
	t.check(String(ov2.call("hitch_summary")).begins_with("hitches:"), "hitch summary text")
	t.eq(ov2.stats.count("frame_ms"), 1, "works with canvas and no tree")
	ov2.get("_canvas").free()
	ov2.free()
