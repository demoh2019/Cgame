extends RefCounted
## Task graph scheduler, CPU budget allocator, lock profiler and scene -> MassEntity conversion.

const TaskGraph = preload("res://scripts/shared/task_graph.gd")
const CpuBudget = preload("res://scripts/shared/cpu_budget.gd")
const LockProfiler = preload("res://scripts/shared/lock_profiler.gd")
const SceneToMass = preload("res://scripts/shared/scene_to_mass.gd")


func _sleep_ms(ms: int) -> bool:
	OS.delay_msec(ms)
	return true


func _sum_range(from: int, to: int) -> int:
	var s := 0
	for i in range(from, to):
		s += i
	return s


func run(t) -> void:
	_test_graph(t)
	_test_budget(t)
	_test_locks(t)
	_test_scene(t)


func _test_graph(t) -> void:
	t.current = "task graph ordering"
	var g := TaskGraph.new()
	g.add_task("a", _sleep_ms.bind(5))
	g.add_task("b", _sleep_ms.bind(5), PackedStringArray(["a"]))
	g.add_task("c", _sleep_ms.bind(5), PackedStringArray(["a"]))
	g.add_task("d", _sleep_ms.bind(5), PackedStringArray(["b", "c"]), false)
	var res := g.run()
	t.check(res["ok"], "graph succeeds")
	t.eq(res["order"], PackedStringArray(["a", "b", "c", "d"]), "deterministic topological order")
	t.eq(res["waves"], 3, "three waves")
	var ta := g.timing("a")
	var tb := g.timing("b")
	var tc := g.timing("c")
	var td := g.timing("d")
	t.check(int(ta["end_us"]) <= int(tb["start_us"]) and int(ta["end_us"]) <= int(tc["start_us"]), "dependants start after a")
	t.check(int(tb["end_us"]) <= int(td["start_us"]) and int(tc["end_us"]) <= int(td["start_us"]), "d waits for b and c")
	t.eq(td["thread_id"], OS.get_thread_caller_id(), "non-thread-safe task runs on the calling thread")
	t.check(float(tb["duration_ms"]) >= 4.0, "per-task timing recorded")

	t.current = "task graph parallel aggregate"
	var p := TaskGraph.new()
	var names := PackedStringArray()
	for i in 16:
		var n := "chunk%d" % i
		p.add_task(n, _sum_range.bind(i * 1000, (i + 1) * 1000))
		names.append(n)
	p.add_task("total", func() -> int:
		var s := 0
		for n in names:
			s += int(p.result_of(n))
		return s, names)
	var pr := p.run()
	t.check(pr["ok"], "parallel graph ok")
	t.eq(p.result_of("total"), _sum_range(0, 16000), "aggregate is correct")
	t.eq(pr["waves"], 2, "independent chunks share a wave")
	t.eq(p.results().keys()[16], "total", "results ordered topologically")

	t.current = "task graph cycles"
	var cg := TaskGraph.new()
	cg.add_task("x", _sleep_ms.bind(0))
	cg.add_task("y", _sleep_ms.bind(0), PackedStringArray(["x"]))
	t.check(not cg.add_dependency("x", "y"), "back edge rejected")
	t.eq(cg.add_task("self", _sleep_ms.bind(0), PackedStringArray(["self"])), "", "self dependency rejected")
	var fwd := TaskGraph.new()
	fwd.add_task("p", _sleep_ms.bind(0), PackedStringArray(["q"]))
	t.eq(fwd.add_task("q", _sleep_ms.bind(0), PackedStringArray(["p"])), "", "forward-reference cycle rejected")
	t.eq(fwd.add_task("dup", _sleep_ms.bind(0)), "dup", "unique name accepted")
	t.eq(fwd.add_task("dup", _sleep_ms.bind(0)), "", "duplicate name rejected")
	t.check(not fwd.run()["ok"], "unknown dependency fails run")

	t.current = "task graph failure"
	var fg := TaskGraph.new()
	fg.add_task("ok1", _sleep_ms.bind(0))
	fg.add_task("bad", func() -> bool: return false, PackedStringArray(["ok1"]))
	fg.add_task("after", _sleep_ms.bind(0), PackedStringArray(["bad"]))
	fg.add_task("after2", _sleep_ms.bind(0), PackedStringArray(["after"]))
	fg.add_task("indep", _sleep_ms.bind(0), PackedStringArray(["ok1"]))
	var fr := fg.run()
	t.check(not fr["ok"], "failure reported")
	t.eq(fr["failed"], PackedStringArray(["bad"]), "failed task listed")
	t.eq(fr["cancelled"], PackedStringArray(["after", "after2"]), "dependants cancelled")
	t.eq(fg.state_of("indep"), TaskGraph.State.DONE, "independent branch still runs")
	t.eq(fg.state_of("after"), TaskGraph.State.CANCELLED, "cancelled state")

	t.current = "task graph critical path"
	var kg := TaskGraph.new()
	kg.add_task("root", _sleep_ms.bind(2))
	kg.add_task("fast", _sleep_ms.bind(2), PackedStringArray(["root"]))
	kg.add_task("slow", _sleep_ms.bind(30), PackedStringArray(["root"]))
	kg.add_task("end", _sleep_ms.bind(2), PackedStringArray(["fast", "slow"]))
	kg.run()
	t.eq(kg.critical_path(), ["root", "slow", "end"], "critical path follows the slowest chain")
	t.check(kg.critical_path_ms() >= 33.0, "critical path length")
	var dot := kg.to_dot()
	t.check(dot.begins_with("digraph TaskGraph"), "dot header")
	t.check(dot.contains("\"root\" -> \"slow\" [color=red]"), "critical edge highlighted")
	t.check(dot.contains("\"root\" -> \"fast\";"), "plain edge")


func _test_budget(t) -> void:
	t.current = "cpu budget"
	var b := CpuBudget.new()
	b.register_system("physics", 4.0, 2.0, 8.0)
	b.register_system("ai", 2.0, 1.0, 6.0)
	b.register_system("audio", 1.0, 0.5, 1.0)
	var a := b.allocate(12.0)
	var total := 0.0
	for k in a:
		total += float(a[k])
	t.near(total, 12.0, 0.001, "budget fully used")
	t.check(float(a["physics"]) >= 2.0 and float(a["ai"]) >= 1.0 and float(a["audio"]) >= 0.5, "minima respected")
	t.near(float(a["audio"]), 1.0, 0.001, "capped at desired")
	t.check(float(a["physics"]) > float(a["ai"]), "higher priority gets more")
	var small := b.allocate(3.0)
	var small_total := 0.0
	for k in small:
		small_total += float(small[k])
	t.near(small_total, 3.0, 0.001, "starved budget is scaled")
	t.near(float(small["physics"]) / float(small["ai"]), 2.0, 0.001, "minima scaled proportionally")
	var roomy := b.allocate(100.0)
	t.near(float(roomy["physics"]), 8.0, 0.001, "never above desired")

	t.current = "cpu budget adaptation"
	var c := CpuBudget.new()
	c.register_system("ai", 1.0, 0.5, 6.0)
	c.register_system("fx", 1.0, 0.5, 6.0)
	for i in 30:
		c.report_usage("ai", 1.0)
		c.report_usage("fx", 5.0)
	var ca := c.allocate(8.0)
	t.check(float(ca["ai"]) < float(ca["fx"]), "idle system yields budget")
	t.near(float(ca["ai"]), 1.25, 0.05, "demand tracks smoothed usage with headroom")
	t.near(float(ca["fx"]), 6.0, 0.001, "freed time flows to the busy system up to its desired cap")
	c.report_usage("ai", 4.0)
	t.check(c.smoothed_usage_ms("ai") > 1.0 and c.smoothed_usage_ms("ai") < 4.0, "smoothing damps spikes")
	for i in 30:
		c.report_usage("fx", 7.5)
	t.check(c.over_budget().has("fx"), "overshoot flagged")
	t.check(not c.over_budget().has("ai") or c.smoothed_usage_ms("ai") > c.allocation_ms("ai"), "over_budget consistent")


func _locked_work(m, ms: int) -> void:
	m.lock()
	OS.delay_msec(ms)
	m.unlock()


func _test_locks(t) -> void:
	t.current = "lock profiler"
	LockProfiler.clear()
	var m := LockProfiler.create("contended")
	var quiet := LockProfiler.create("quiet")
	quiet.lock()
	quiet.unlock()
	m.lock()
	var id := WorkerThreadPool.add_task(_locked_work.bind(m, 1))
	OS.delay_msec(30)
	m.unlock()
	WorkerThreadPool.wait_for_task_completion(id)
	t.eq(m.acquisitions, 2, "acquisitions counted")
	t.eq(m.contended, 1, "worker waited on the main thread")
	t.check(float(m.stats()["total_wait_ms"]) >= 15.0, "wait time recorded")
	t.check(float(m.stats()["total_hold_ms"]) >= 25.0, "hold time recorded")
	t.check(m.owner_thread_id != 0, "owner thread recorded")
	var rep := LockProfiler.report()
	t.eq(rep[0]["name"], "contended", "report sorted by wait")
	t.eq(rep[1]["contended"], 0, "uncontended mutex has no waits")

	var ids: Array[int] = []
	var m2 := LockProfiler.create("many")
	for i in 4:
		ids.append(WorkerThreadPool.add_task(_locked_work.bind(m2, 3)))
	for i in ids:
		WorkerThreadPool.wait_for_task_completion(i)
	t.eq(m2.acquisitions, 4, "all pooled acquisitions recorded")
	t.check(m2.try_lock(), "try_lock succeeds when free")
	m2.unlock()

	t.current = "sync points"
	LockProfiler.long_sync_threshold_ms = 5.0
	var r: Variant = LockProfiler.sync_point("slow_readback", func() -> int:
		OS.delay_msec(12)
		return 7)
	LockProfiler.sync_point("fast", func() -> int: return 1)
	t.eq(r, 7, "sync_point passes the result through")
	t.eq(LockProfiler.long_syncs(), PackedStringArray(["slow_readback"]), "only the long sync is flagged")
	t.eq(LockProfiler.sync_report()[0]["name"], "slow_readback", "sync report sorted by time")
	LockProfiler.clear()


func _test_scene(t) -> void:
	t.current = "scene to mass"
	var root := Node3D.new()
	for i in 200:
		var n := Node3D.new()
		n.position = Vector3(i, i * 2.0, -i)
		n.set_meta("mass", true)
		root.add_child(n)
	var other := Node3D.new()
	root.add_child(other)
	var rules: Array = [{"meta": "mass", "map": {"pos": "position"}, "action": "keep"}]
	var res := SceneToMass.convert(root, rules)
	var mass = res["mass"]
	var mapping: Array = res["mapping"]
	t.eq(res["converted"], 200, "200 nodes converted")
	t.eq(mass.entity_count(), 200, "entities created")
	t.eq(mass.get_value(mapping[7]["id"], "pos"), Vector3(7, 14, -7), "position copied to pos fragment")
	for e in mapping:
		mass.set_value(e["id"], "pos", mass.get_value(e["id"], "pos") + Vector3(0, 1, 0))
	t.eq(SceneToMass.sync_back(mass, mapping), 200, "all nodes synced")
	t.eq((mapping[9]["node"] as Node3D).position, Vector3(9, 19, -9), "fragment value written back")

	var free_rules: Array = [{"meta": "mass", "map": {"pos": "position"}, "action": "free"}]
	var res2 := SceneToMass.convert(root, free_rules)
	t.eq(res2["freed"], 200, "nodes freed")
	t.eq(root.get_child_count(), 1, "only unmatched node remains")
	t.eq(res2["mass"].entity_count(), 200, "entities survive node removal")
	t.eq(SceneToMass.sync_back(res2["mass"], res2["mapping"]), 0, "freed nodes are skipped")
	other.free()
	root.free()

	t.current = "storage heuristic"
	t.eq(SceneToMass.choose_storage(10, "iterate"), "node", "few objects stay nodes")
	t.eq(SceneToMass.choose_storage(5000, "iterate"), "mass_soa", "bulk iteration uses SoA")
	t.eq(SceneToMass.choose_storage(2000, "sparse"), "mass_sparse", "sparse activation")
	t.eq(SceneToMass.choose_storage(200, "random"), "node", "random access small set")
