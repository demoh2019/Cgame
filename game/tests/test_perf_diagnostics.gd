extends RefCounted
## Perf capture format, scenario replay, regression, asset I/O, memory, shader stall, GPU crash.

const Fmt = preload("res://scripts/tools/perf_capture_format.gd")
const Scenario = preload("res://scripts/tools/perf_scenario.gd")
const AssetIO = preload("res://scripts/tools/asset_io_profiler.gd")
const MemLife = preload("res://scripts/tools/memory_lifetime.gd")
const ShaderStall = preload("res://scripts/tools/shader_stall_analyzer.gd")
const GpuCrash = preload("res://scripts/tools/gpu_crash_analyzer.gd")


class Dummy:
	extends Object


func _make_cap(render_us: float, ai_us: float) -> Dictionary:
	var cap: Dictionary = Fmt.new_capture("t")
	for i in 20:
		Fmt.add_frame(cap, i, 10.0, {"render/draw": render_us, "render/shadow": render_us, "ai/think": ai_us, "net/recv": 100.0})
	return cap


func run(t) -> void:
	t.current = "capture round trip"
	var cap: Dictionary = _make_cap(2000.0, 1000.0)
	Fmt.add_event(cap, "memory_samples", {"objects": 5})
	Fmt.add_event(cap, "network_packets", {"bytes": 64})
	Fmt.add_event(cap, "bogus", {})
	t.eq(Fmt.validate(cap).size(), 0, "fresh capture valid")
	var path := "user://test_capture.cgperf"
	t.check(Fmt.write(path, cap), "write bytes")
	var back: Dictionary = Fmt.read(path)
	t.eq(back.get("version"), Fmt.VERSION, "version kept")
	var bf: Array = back["frames"]
	t.eq(bf.size(), 20, "frames kept")
	var ms: PackedFloat32Array = Fmt.frame_times(back)
	t.near(ms[3], 10.0, 0.001, "frame time")
	var mem: Array = back["memory_samples"]
	t.eq(mem.size(), 1, "memory samples kept")
	var jpath := "user://test_capture.json"
	t.check(Fmt.write(jpath, cap), "write json")
	var jb: Dictionary = Fmt.read(jpath)
	t.eq(Fmt.validate(jb).size(), 0, "json read back valid")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(jpath)
	t.eq(Fmt.read("user://does_not_exist.cgperf").size(), 0, "missing file gives empty")

	t.current = "capture validation"
	var bad: Dictionary = cap.duplicate(true)
	bad["magic"] = "nope"
	bad.erase("network_packets")
	bad["version"] = 99
	t.check(Fmt.validate(bad).size() >= 3, "bad magic, section and version caught")
	var bad2: Dictionary = cap.duplicate(true)
	var bf2: Array = bad2["frames"]
	bf2.append({"ms": "slow"})
	t.check(Fmt.validate(bad2).size() > 0, "non-numeric ms caught")
	var merged: Dictionary = Fmt.merge(cap, _make_cap(1.0, 1.0))
	var mf: Array = merged["frames"]
	t.eq(mf.size(), 40, "merge concatenates frames")

	t.current = "scenario replay"
	var sc := Scenario.new()
	sc.start_recording(42)
	for f in 10:
		var x := Transform3D(Basis(Vector3.UP, 0.1 * f), Vector3(f, 2.0, -f * 0.5))
		sc.record_frame(f * 2, x, [{"action": "fwd", "pressed": f % 2 == 0}])
	sc.stop_recording()
	var data: Dictionary = sc.to_dict()
	var r1 := Scenario.new()
	var r2 := Scenario.new()
	t.check(r1.load_scenario(data) and r2.load_scenario(data), "scenario loads")
	var cam1 := Camera3D.new()
	var cam2 := Camera3D.new()
	var same: bool = true
	for f in 20:
		r1.step(f, cam1)
		r2.step(f, cam2)
		if not cam1.transform.is_equal_approx(cam2.transform):
			same = false
	t.check(same, "replays identical")
	r1.step(8, cam1)
	t.near(cam1.position.x, 4.0, 0.0001, "exact frame matches recording")
	r1.step(9, cam1)
	t.near(cam1.position.x, 4.5, 0.0001, "in-between frame interpolates")
	var ins: Array = r1.step(4, cam1)
	t.eq(ins.size(), 1, "inputs replayed")
	t.eq(r1.seed_value, 42, "seed kept")
	cam1.free()
	cam2.free()
	var cap_sc: Dictionary = Fmt.new_capture()
	cap_sc["scenario"] = data
	var rt: Dictionary = bytes_to_var(var_to_bytes(cap_sc))
	var r3 := Scenario.new()
	t.check(r3.load_scenario(rt["scenario"]), "scenario survives capture round trip")

	t.current = "subsystem regression"
	var base: Dictionary = _make_cap(2000.0, 1000.0)
	var cur: Dictionary = _make_cap(3000.0, 1000.0)
	var cmp: Dictionary = Scenario.compare_captures(base, cur)
	var regs: Array = cmp["regressions"]
	t.check(regs.has("render"), "render regression flagged")
	t.check(not regs.has("ai"), "ai unchanged not flagged")
	t.check(not regs.has("net"), "net unchanged not flagged")
	var subs: Dictionary = cmp["subsystems"]
	var rd: Dictionary = subs["render"]
	t.near(float(rd["mean_pct"]), 50.0, 0.01, "render +50 percent")
	var cmp2: Dictionary = Scenario.compare_captures(cur, base)
	var imps: Array = cmp2["improvements"]
	t.check(imps.has("render"), "improvement detected")
	var cmp3: Dictionary = Scenario.compare_captures(base, cur, {"render": 80.0})
	var regs3: Array = cmp3["regressions"]
	t.check(not regs3.has("render"), "per-subsystem threshold respected")

	t.current = "asset io profiler"
	var res_path := "user://test_io_res.tres"
	var gen := Gradient.new()
	t.eq(ResourceSaver.save(gen, res_path), OK, "saved test resource")
	var io := AssetIO.new()
	var loaded: Resource = io.load_timed(res_path)
	t.check(loaded != null, "loaded resource")
	t.eq(io.entries.size(), 1, "one entry")
	var e0: Dictionary = io.entries[0]
	t.check(int(e0["bytes"]) > 0, "bytes recorded")
	t.check(int(e0["dur_usec"]) >= 0 and bool(e0["ok"]), "duration and ok recorded")
	t.eq(str(e0["ext"]), "tres", "ext recorded")
	t.check(io.request_threaded(res_path), "threaded request accepted")
	var guard: int = 0
	while io.pending_count() > 0 and guard < 500:
		io.poll()
		OS.delay_msec(2)
		guard += 1
	t.eq(io.pending_count(), 0, "threaded load finished")
	var e2: Dictionary = io.entries[io.entries.size() - 1]
	t.eq(str(e2["kind"]), "threaded", "threaded entry kind")
	var timeline: Array[Dictionary] = io.export_timeline()
	t.eq(timeline.size(), io.entries.size(), "timeline rows")
	t.eq(int(timeline[0]["ts"]), 0, "timeline starts at zero")
	var summ: Dictionary = io.summary()
	t.check(summ.has("tres"), "summary by ext")
	t.check(io.export_chrome_json().contains("traceEvents"), "chrome json export")
	DirAccess.remove_absolute(res_path)

	t.current = "memory lifetime"
	var ml := MemLife.new()
	var keep: Array[Object] = []
	var temp: Array[Object] = []
	for i in 3:
		var d := Dummy.new()
		temp.append(d)
		ml.track(d, "temp")
	var leak_seed := Dummy.new()
	keep.append(leak_seed)
	ml.track(leak_seed, "leaky")
	ml.sample()
	for i in 6:
		var d := Dummy.new()
		keep.append(d)
		ml.track(d, "leaky")
		ml.sample()
		if i == 1:
			for o in temp:
				o.free()
			temp.clear()
	var suspects: Array[Dictionary] = ml.leak_suspects(5, 2)
	t.eq(suspects.size(), 1, "single leak suspect")
	if suspects.size() > 0:
		t.eq(str(suspects[0]["tag"]), "leaky", "leaky tag flagged")
	var ls: Dictionary = ml.lifetime_stats()
	t.check(ls.has("temp"), "freed tag has lifetimes")
	var frees: int = 0
	for ev in ml.events:
		if str(ev["type"]) == "free":
			frees += 1
	t.eq(frees, 3, "three free events")
	t.eq(ml.export_samples().size(), 7, "samples exported")
	for o in keep:
		o.free()

	t.current = "shader stall analyzer"
	var ss := ShaderStall.new()
	for i in 30:
		ss.feed(i, 8.0, 0)
	ss.feed(30, 40.0, 3, ["res://mat/lava.tres", "res://mat/smoke.tres"])
	ss.feed(31, 9.0, 0)
	ss.feed(32, 45.0, 2, ["res://mat/lava.tres"])
	ss.feed(33, 50.0, 0)
	var rep: Dictionary = ss.analyze()
	var stalls: Array = rep["stalls"]
	t.eq(stalls.size(), 2, "two compile stalls")
	var unrel: Array = rep["unrelated_spikes"]
	t.eq(unrel.size(), 1, "spike without compiles is unrelated")
	var culprits: Array = rep["culprits"]
	var top: Dictionary = culprits[0]
	t.eq(str(top["material"]), "res://mat/lava.tres", "lava is top culprit")
	t.eq(int(top["stalls"]), 2, "lava stalled twice")
	var ss2 := ShaderStall.new()
	ss2.feed_cumulative(0, 8.0, 10)
	ss2.feed_cumulative(1, 8.0, 10)
	ss2.feed_cumulative(2, 8.0, 10)
	ss2.feed_cumulative(3, 30.0, 14, ["m"])
	var rep2: Dictionary = ss2.analyze()
	var st2: Array = rep2["stalls"]
	t.eq(st2.size(), 1, "cumulative counter delta")
	t.check(ShaderStall.live_compile_total() >= 0, "live counter safe")

	t.current = "gpu crash analyzer"
	var log_text := "\n".join([
		"ERROR: vkQueueSubmit failed: VK_ERROR_DEVICE_LOST",
		"Execution of command buffer failed: MTLCommandBufferErrorTimeout",
		"ERROR: VK_ERROR_OUT_OF_DEVICE_MEMORY while allocating image",
		"ERROR: Shader compilation failed: unexpected token",
		"ERROR: Condition \"!texture\" is true. Returning: RID()",
		"ERROR: Condition \"!texture\" is true. Returning: RID()",
		"all fine here",
	])
	var reports: Array[Dictionary] = GpuCrash.parse(log_text)
	var kinds: Array[String] = []
	for r in reports:
		kinds.append(str(r["kind"]))
	t.check(kinds.has("device_lost"), "device lost parsed")
	t.check(kinds.has("metal_error"), "metal error parsed")
	t.check(kinds.has("out_of_memory"), "oom parsed")
	t.check(kinds.has("shader_compile"), "shader compile parsed")
	t.check(kinds.has("condition_true"), "condition parsed")
	t.eq(reports.size(), 5, "duplicates folded")
	var cond: Dictionary = reports[4]
	t.eq(int(cond["count"]), 2, "duplicate counted")
	var sug: Array = cond["suggestions"]
	t.check(str(cond["likely_cause"]).length() > 0 and sug.size() > 0, "cause and suggestions present")
	t.eq(GpuCrash.parse("nothing wrong").size(), 0, "clean log has no reports")
	t.eq(str(GpuCrash.summarize(reports)["primary_kind"]), "device_lost", "primary kind is most severe")
