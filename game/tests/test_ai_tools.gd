extends RefCounted
## AI tooling: planning debug recorder, spatial query graph, editor panels (headless APIs).

const Recorder = preload("res://scripts/shared/ai_debug_recorder.gd")
const SQG = preload("res://scripts/shared/spatial_query_graph.gd")
const UtilityAI = preload("res://scripts/shared/utility_ai.gd")
const DebugPanel = preload("res://addons/cgame_ai_tools/ai_debug_panel.gd")
const QueryPanel = preload("res://addons/cgame_ai_tools/query_panel.gd")
const SmartPanel = preload("res://addons/cgame_ai_tools/smart_object_panel.gd")


func run(t) -> void:
	_recorder(t)
	_query(t)
	_panels(t)


func _recorder(t) -> void:
	t.current = "ai recorder ring buffer"
	var r := Recorder.new(4)
	for i in 10:
		r.record_goap("a", ["x", "y"], float(i), float(i))
	t.eq(r.count("a"), 4, "ring buffer is bounded")
	t.eq(r.dropped("a"), 6, "overwritten records counted")
	var tl := r.timeline("a", 0.0, 100.0)
	t.near(float(tl[0]["time"]), 6.0, 0.001, "oldest kept record")
	t.eq(r.timeline("a", 7.0, 8.0).size(), 2, "timeline window filters")
	t.eq(r.timeline("missing", 0.0, 9.0).size(), 0, "unknown agent is empty")

	t.current = "ai recorder kinds and explain"
	var rec := Recorder.new()
	rec.set_time(1.0)
	rec.record_htn("npc", ["go", "attack"], {"hp": 5})
	rec.record_state_tree("npc", "Root/Combat")
	rec.record_utility("npc", {"attack": 0.8, "flee": 0.2, "idle": 0.1}, "attack")
	rec.advance(1.0)
	rec.record_htn("npc", ["go", "heal"], {"hp": 1})
	rec.record_goap("npc", ["a", "b"], 3.0)
	t.eq(rec.timeline("npc", 0.0, 5.0, "htn").size(), 2, "kind filter")
	t.eq(rec.latest("npc", "state_tree", 1.5)["data"]["path"], ["Root", "Combat"], "state tree path split")
	var text := rec.explain("npc", 1.5)
	t.check(text.contains("chose 'attack'") and text.contains("margin"), "explain utility")
	t.check(text.contains("Root/Combat"), "explain state tree")
	t.check(rec.explain("npc", 2.5).contains("Replanned") and rec.explain("npc", 2.5).contains("heal"), "explain replan")
	t.check(rec.explain("nobody", 1.0).begins_with("No decisions"), "explain empty")
	rec.record_utility("npc", {"a": 0.9, "b": 0.5}, "b", 3.0)
	t.check(rec.explain("npc", 3.0).contains("not chosen"), "explain notes overridden choice")
	var parsed: Variant = JSON.parse_string(rec.export_json())
	t.check(parsed is Dictionary and (parsed as Dictionary)["agents"].has("npc"), "export_json round trips")

	t.current = "ai recorder diff"
	var d := Recorder.diff_plans(["a", "b", "c"], ["a", "x"])
	t.eq(d["common_prefix"], 1, "diff prefix")
	t.eq(d["removed"], ["b", "c"], "diff removed")
	t.eq(d["added"], ["x"], "diff added")
	t.check(Recorder.diff_plans(["a", "b"], ["b", "a"])["reordered"], "diff reorder")
	t.check(Recorder.diff_plans(["a"], ["a"])["same"], "diff same")
	t.eq(rec.plan_changes("npc", "htn").size(), 2, "plan_changes lists first plan and the change")


func _query(t) -> void:
	t.current = "query generators"
	var ctx: Dictionary = {"querier": Vector3(10, 0, 10), "facing": Vector3(1, 0, 0), "target": Vector3(30, 0, 10),
			"actors": [{"position": Vector3(12, 0, 10), "type": "enemy", "id": "e1"},
					{"position": Vector3(50, 0, 10), "type": "enemy", "id": "far"},
					{"position": Vector3(11, 0, 10), "type": "ally", "id": "a1"}],
			"navmesh_points": func(c: Vector3, _r: float, n: int) -> Array:
				var out: Array = []
				for i in n:
					out.append(c + Vector3(float(i), 0, 0))
				return out}
	var q := SQG.new()
	var a := SQG.new_asset()
	SQG.add_generator(a, SQG.make_generator("grid", {"half_extents": 4.0, "spacing": 2.0}))
	t.eq(q.run(a, ctx).size(), 25, "grid 5x5")
	a = SQG.new_asset()
	SQG.add_generator(a, SQG.make_generator("ring", {"radius": 5.0, "count": 12}))
	var ring := q.run(a, ctx)
	t.eq(ring.size(), 12, "ring count")
	t.near((ring[0]["position"] as Vector3).distance_to(Vector3(10, 0, 10)), 5.0, 0.001, "ring radius")
	a = SQG.new_asset()
	SQG.add_generator(a, SQG.make_generator("navmesh", {"count": 7}))
	t.eq(q.run(a, ctx).size(), 7, "navmesh callable points")
	a = SQG.new_asset()
	SQG.add_generator(a, SQG.make_generator("actors", {"actor_type": "enemy", "radius": 20.0}))
	var act := q.run(a, ctx)
	t.eq(act.size(), 1, "actors filtered by type and radius")
	t.eq(act[0]["actor"], "e1", "actor id carried")
	t.check(SQG.validate(SQG.new_asset()).size() == 1, "validate flags empty generators")

	t.current = "query tests and scoring"
	a = SQG.new_asset()
	SQG.add_generator(a, SQG.make_generator("grid", {"half_extents": 6.0, "spacing": 2.0}))
	SQG.add_test(a, SQG.make_test("distance", {"max": 10.0, "invert": true}))
	var scored := q.run(a, ctx)
	t.near(float(scored[0]["score"]), 1.0, 0.001, "closest item scores 1")
	var sorted_ok := true
	for i in range(1, scored.size()):
		if float(scored[i]["score"]) > float(scored[i - 1]["score"]):
			sorted_ok = false
	t.check(sorted_ok, "results sorted by score")
	t.check(q.debug()["tests"]["distance_0"]["evaluated"] == 49, "debug counts evaluations")

	SQG.add_test(a, SQG.make_test("dot", {"filter_min": 0.0, "score": false}))
	var fwd := q.run(a, ctx)
	var all_forward := true
	for it in fwd:
		if (it["position"] as Vector3).x < 10.0:
			all_forward = false
	t.check(all_forward and fwd.size() < 49 and fwd.size() > 0, "dot filter keeps forward half")
	t.check(int(q.debug()["filtered_by"]["dot_1"]) > 0, "debug counts filtered items")

	SQG.add_test(a, SQG.make_test("trace", {"filter_min": 0.5}))
	ctx["trace"] = func(_from: Vector3, to: Vector3) -> bool: return to.z <= 10.0
	var vis := q.run(a, ctx)
	var vis_ok := true
	for it in vis:
		if (it["position"] as Vector3).z > 10.0:
			vis_ok = false
	t.check(vis_ok and vis.size() > 0, "trace callable filters")

	var b := SQG.new_asset()
	SQG.add_generator(b, SQG.make_generator("ring", {"radius": 5.0, "count": 8}))
	SQG.add_test(b, SQG.make_test("path_length", {"max": 10.0, "invert": true, "filter_max": 8.0}))
	ctx["path_length"] = func(_f: Vector3, to: Vector3) -> float: return -1.0 if to.z > 12.0 else 6.0
	var pathed := q.run(b, ctx)
	t.check(pathed.size() > 0 and pathed.size() < 8, "unreachable items filtered by path_length")
	SQG.add_test(b, SQG.make_test("custom", {"callable": "mine", "weight": 2.0}))
	ctx["custom"] = {"mine": func(p: Vector3, _c: Dictionary, _i: Dictionary) -> float: return 1.0 if p.x > 10.0 else 0.0}
	var cust := q.run(b, ctx)
	t.check(cust.size() > 0 and (cust[0]["position"] as Vector3).x > 10.0, "custom test scores")
	b["combine"] = "iaus"
	b["max_results"] = 2
	t.eq(q.run(b, ctx).size(), 2, "max_results truncates")

	t.current = "query time slicing"
	var c := SQG.new_asset()
	SQG.add_generator(c, SQG.make_generator("grid", {"half_extents": 8.0, "spacing": 1.0}))
	SQG.add_test(c, SQG.make_test("distance", {"max": 12.0, "invert": true, "curve": UtilityAI.Response.QUADRATIC}))
	SQG.add_test(c, SQG.make_test("dot", {"weight": 0.5}))
	var full := SQG.new().run(c, ctx).duplicate()
	var s := SQG.new()
	var n := s.start(c, ctx)
	t.eq(n, 289, "17x17 grid generated")
	var steps := 0
	while not s.step(40):
		steps += 1
		t.check(s.progress() < 1.0, "progress < 1 mid run")
	t.check(steps >= 6 and s.is_done(), "multiple steps executed")
	var sliced := s.results()
	var same := full.size() == sliced.size()
	if same:
		for i in full.size():
			if int(full[i]["index"]) != int(sliced[i]["index"]) or absf(float(full[i]["score"]) - float(sliced[i]["score"])) > 0.00001:
				same = false
	t.check(same, "sliced run equals full run")
	t.check(int(s.debug()["steps"]) > 1, "debug reports step count")


func _panels(t) -> void:
	t.current = "ai debug panel"
	var rec := Recorder.new()
	rec.record_state_tree("p", ["A", "B"], 0.0)
	rec.record_state_tree("p", ["A", "B"], 1.0)
	rec.record_state_tree("p", ["A", "C"], 2.0)
	rec.record_utility("p", {"x": 0.3, "y": 0.6}, "y", 1.0)
	rec.record_htn("p", ["a"], {}, 0.5)
	var dp := DebugPanel.new()
	t.check(dp.explain_at() == "No agent selected.", "no recorder yet")
	dp.set_recorder(rec)
	t.eq(dp.selected_agent, "p", "first agent auto selected")
	var view := dp.build_view()
	var spans: Array = view["lanes"]["state_tree"]
	t.eq(spans.size(), 2, "state tree spans merged")
	t.eq((view["lanes"]["utility"]["series"] as Dictionary).size(), 2, "utility series per option")
	t.eq((view["lanes"]["htn"] as Array).size(), 1, "htn marks")
	dp.set_cursor(2.0)
	t.check(dp.explain_at().contains("Root") or dp.explain_at().contains("A/C"), "explain at cursor")
	dp.set_range(0.0, 0.7)
	t.eq((dp.build_view()["lanes"]["state_tree"] as Array).size(), 1, "range limits view")
	dp.free()

	t.current = "query panel"
	var qp := QueryPanel.new()
	var gi := qp.add_generator("grid", {"half_extents": 4.0, "spacing": 2.0})
	var ti := qp.add_test("distance", {"max": 8.0, "invert": true})
	t.eq([gi, ti], [0, 0], "indices returned")
	var pts := qp.run_preview()
	t.eq(pts.size(), 25, "preview scored points")
	t.check(float(pts[0]["score"]) >= float(pts[pts.size() - 1]["score"]), "preview sorted")
	qp.add_generator("navmesh", {"count": 5})
	t.eq(qp.run_preview().size(), 30, "navmesh fallback adds points")
	t.check(qp.set_test_param(0, "weight", 2.0), "set param")
	t.check(qp.asset_json().contains("distance"), "asset exports json")
	t.check(qp.remove_generator(1) and qp.remove_test(0) and not qp.remove_test(5), "remove entries")
	t.eq(qp.run_preview().size(), 25, "preview after removal")
	qp.free()

	t.current = "smart object panel"
	var sp := SmartPanel.new()
	t.check(sp.place_object("bench", Vector3(1, 0, 2), ["seat"]), "place")
	t.check(not sp.place_object("bench", Vector3.ZERO), "duplicate id rejected")
	t.eq(sp.add_slot("bench", Vector3(0.5, 0, 0), "sit"), 0, "add slot")
	t.check(sp.move_slot("bench", 0, Vector3(1, 0, 0)), "move slot")
	t.check(sp.move_object("bench", Vector3(4, 0, 4)), "move object")
	t.eq(sp.registry.object_count(), 1, "registry mirrors")
	t.eq(sp.registry.find({"position": Vector3(4, 0, 4), "radius": 5.0, "behavior": "sit"}).size(), 1, "registry find sees slot")
	var preview := sp.preview_auto_place(Rect2(0, 0, 20, 20), 5, {"min_spacing": 2.0}, 7)
	t.check(preview.size() > 0 and sp.object_ids().size() == 1, "preview does not commit")
	var made := sp.commit_auto_place(Rect2(0, 0, 20, 20), 5, {"min_spacing": 2.0}, 7, {"tags": ["seat"], "slots": [{"offset": Vector3(1, 0, 0), "behavior": "sit"}]})
	t.eq(made.size(), preview.size(), "commit matches preview (deterministic seed)")
	var json := sp.export_json()
	var sp2 := SmartPanel.new()
	t.check(sp2.import_json(json), "import")
	t.eq(sp2.object_ids(), sp.object_ids(), "round trip ids")
	t.eq(sp2.registry.object_count(), sp.registry.object_count(), "import registers objects")
	t.check(sp.delete_slot("bench", 0) and sp.delete_object("bench") and not sp.delete_object("bench"), "delete slot and object")
	t.check(not sp.import_json("nope"), "bad json rejected")
	sp.free()
	sp2.free()
