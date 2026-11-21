extends RefCounted
## StateTree runtime and Smart Object registry.

const StateTree = preload("res://scripts/shared/state_tree.gd")
const SmartObjects = preload("res://scripts/shared/smart_objects.gd")

var _log: Array[String] = []


func _tree() -> StateTree:
	var st := StateTree.new()
	_log = []
	# "work" completes after ctx.work_ticks ticks, "fail_task" fails at once, "idle" never ends.
	st.register_task("work",
		func(_c: Dictionary, p: Dictionary) -> void: _log.append("enter:" + str(p["_state"])),
		func(c: Dictionary, _dt: float, _p: Dictionary) -> int:
			c["work_done"] = int(c.get("work_done", 0)) + 1
			return StateTree.Status.SUCCEEDED if int(c["work_done"]) >= int(c.get("work_ticks", 1)) else StateTree.Status.RUNNING,
		func(_c: Dictionary, p: Dictionary) -> void: _log.append("exit:" + str(p["_state"])))
	st.register_task("fail_task", Callable(),
		func(_c: Dictionary, _dt: float, _p: Dictionary) -> int: return StateTree.Status.FAILED)
	st.register_task("idle",
		func(_c: Dictionary, p: Dictionary) -> void: _log.append("enter:" + str(p["_state"])),
		Callable(),
		func(_c: Dictionary, p: Dictionary) -> void: _log.append("exit:" + str(p["_state"])))
	st.register_condition("has_ammo", func(c: Dictionary, _a: Dictionary) -> bool: return int(c.get("ammo", 0)) > 0)
	st.register_condition("flag", func(c: Dictionary, a: Dictionary) -> bool: return bool(c.get(str(a["name"]), false)))
	return st


func _basic_asset() -> Dictionary:
	return {
		"root": "root",
		"states": {
			"root": {"children": ["combat", "patrol", "rest"]},
			"combat": {"conditions": ["has_ammo"], "tasks": ["idle"]},
			"patrol": {"children": ["walk", "look"], "conditions": [{"key": "alert", "op": "<", "value": 5}]},
			"walk": {"tasks": ["work"], "transitions": [{"trigger": "on_completed", "target": "look"}]},
			"look": {"tasks": ["idle"]},
			"rest": {"tasks": ["idle"]},
		},
	}


func run(t) -> void:
	_run_selection(t)
	_run_transitions(t)
	_run_enter_exit(t)
	_run_evaluators_and_links(t)
	_run_validation(t)
	_run_smart_objects(t)
	_run_interactions(t)


func _run_selection(t) -> void:
	t.current = "state tree selection"
	var st := _tree()
	t.check(st.set_asset(_basic_asset()), "valid asset installs: %s" % str(st.errors))
	var ctx: Dictionary = {"alert": 0}
	t.check(st.start(ctx), "tree starts")
	t.eq(st.debug_path(), "root/patrol/walk", "first passing child is picked depth-first")
	st.stop(ctx)
	ctx = {"alert": 0, "ammo": 3}
	st.start(ctx)
	t.eq(st.debug_path(), "root/combat", "enter conditions pick the earlier sibling")
	st.stop(ctx)
	ctx = {"alert": 9}
	st.start(ctx)
	t.eq(st.debug_path(), "root/rest", "failed enter conditions fall through to later sibling")
	t.check(not st.is_active("patrol"), "skipped state is not active")
	t.eq(st.current_state(), "rest", "current state is the leaf")


func _run_transitions(t) -> void:
	t.current = "state tree transitions"
	var st := _tree()
	st.set_asset(_basic_asset())
	var ctx: Dictionary = {"alert": 0, "work_ticks": 2}
	st.start(ctx)
	st.tick(0.1, ctx)
	t.eq(st.debug_path(), "root/patrol/walk", "task still running after first tick")
	st.tick(0.1, ctx)
	t.eq(st.debug_path(), "root/patrol/look", "on_completed moves to the target")

	# on_failed and priority resolution
	st = _tree()
	st.set_asset({
		"root": "r",
		"states": {
			"r": {"children": ["a", "b", "c"]},
			"a": {"tasks": ["fail_task"], "transitions": [
				{"trigger": "on_failed", "target": "b", "priority": 1},
				{"trigger": "on_failed", "target": "c", "priority": 5},
			]},
			"b": {"tasks": ["idle"]},
			"c": {"tasks": ["idle"]},
		},
	})
	ctx = {}
	st.start(ctx)
	st.tick(0.1, ctx)
	t.eq(st.debug_path(), "r/c", "higher priority failure transition wins")

	# events and conditions
	st = _tree()
	st.set_asset({
		"root": "r",
		"states": {
			"r": {"children": ["a", "b", "c"]},
			"a": {"tasks": ["idle"], "transitions": [
				{"trigger": "on_event", "event": "alarm", "target": "b"},
				{"trigger": "on_tick", "condition": {"fn": "flag", "args": {"name": "go_c"}}, "target": "c"},
			]},
			"b": {"tasks": ["idle"]},
			"c": {"tasks": ["idle"]},
		},
	})
	ctx = {}
	st.start(ctx)
	st.send_event("noise")
	st.tick(0.1, ctx)
	t.eq(st.current_state(), "a", "unrelated event is ignored")
	st.send_event("alarm", {"x": 1})
	st.tick(0.1, ctx)
	t.eq(st.current_state(), "b", "matching event transitions")
	st.stop(ctx)
	st.start(ctx)
	ctx["go_c"] = true
	st.tick(0.1, ctx)
	t.eq(st.current_state(), "c", "on_tick transition fires when its condition passes")

	# unselectable target is skipped, tree finishes when nothing handles completion
	st = _tree()
	st.set_asset({
		"root": "r",
		"states": {
			"r": {"children": ["a", "b"]},
			"a": {"tasks": ["work"], "transitions": [
				{"trigger": "on_completed", "target": "b", "priority": 9, "condition": "has_ammo"},
			]},
			"b": {"tasks": ["idle"]},
		},
	})
	ctx = {"work_ticks": 1}
	st.start(ctx)
	st.tick(0.1, ctx)
	t.eq(st.tree_status, StateTree.Status.SUCCEEDED, "unhandled completion finishes the tree")
	t.check(not st.running, "finished tree stops running")
	t.eq(st.debug_path(), "(inactive)", "no active path after finish")


func _run_enter_exit(t) -> void:
	t.current = "state tree enter/exit order"
	var st := _tree()
	st.set_asset({
		"root": "root",
		"states": {
			"root": {"children": ["p", "q"]},
			"p": {"children": ["p1", "p2"], "tasks": ["idle"]},
			"p1": {"tasks": ["work"], "transitions": [{"trigger": "on_completed", "target": "p2"}]},
			"p2": {"tasks": ["work"], "transitions": [{"trigger": "on_completed", "target": "q"}]},
			"q": {"tasks": ["idle"]},
		},
	})
	var ctx: Dictionary = {"work_ticks": 1}
	st.start(ctx)
	t.eq(_log, ["enter:p", "enter:p1"], "enter runs outer to inner")
	_log.clear()
	ctx["work_done"] = 0
	st.tick(0.1, ctx)
	t.eq(_log, ["exit:p1", "enter:p2"], "sibling switch keeps shared parent active")
	_log.clear()
	ctx["work_done"] = 0
	st.tick(0.1, ctx)
	t.eq(_log, ["exit:p2", "exit:p", "enter:q"], "leaving a branch exits inner to outer")
	_log.clear()
	st.stop(ctx)
	t.eq(_log, ["exit:q"], "stop exits the active path")

	# re-entering the already active state restarts it
	st = _tree()
	st.set_asset({
		"root": "r",
		"states": {"r": {"children": ["a"]},
			"a": {"tasks": ["idle"], "transitions": [{"trigger": "on_event", "event": "again", "target": "a"}]}},
	})
	ctx = {}
	st.start(ctx)
	_log.clear()
	st.send_event("again")
	st.tick(0.1, ctx)
	t.eq(_log, ["exit:a", "enter:a"], "self transition re-enters")


func _run_evaluators_and_links(t) -> void:
	t.current = "state tree evaluators and subtrees"
	var st := _tree()
	st.register_evaluator("clock", func(c: Dictionary, dt: float, a: Dictionary) -> Dictionary:
		return {"time": float(c.get("time", 0.0)) + dt, "step": a["step"]})
	st.register_subtree("hunt", {
		"root": "h",
		"states": {"h": {"children": ["chase", "search"]},
			"chase": {"conditions": [{"key": "seen", "op": "==", "value": true}], "tasks": ["idle"]},
			"search": {"tasks": ["idle"], "transitions": [{"trigger": "on_event", "event": "done", "target": "$succeeded"}]}},
	})
	t.check(st.set_asset({
		"root": "r",
		"evaluators": [{"fn": "clock", "args": {"step": 7}}],
		"states": {
			"r": {"children": ["wait", "hunting"]},
			"wait": {"conditions": [{"key": "time", "op": "<", "value": 0.25}], "tasks": ["idle"]},
			"hunting": {"link": "hunt"},
		},
	}), "asset with link installs: %s" % str(st.errors))
	var ctx: Dictionary = {"time": 0.0, "seen": false}
	st.start(ctx)
	t.eq(st.current_state(), "wait", "time condition passes initially")
	st.tick(0.1, ctx)
	t.near(float(ctx["time"]), 0.1, 0.0001, "evaluator writes into context")
	t.eq(ctx["step"], 7, "evaluator receives args")
	st.stop(ctx)
	ctx["time"] = 1.0
	ctx["seen"] = true
	st.start(ctx)
	t.eq(st.debug_path(), "r/hunting/hunting/h/hunting/chase",
		"linked subtree states are namespaced under the linking state")
	t.check(st.is_active("hunting/chase"), "subtree leaf active with namespaced id")
	st.stop(ctx)
	ctx["seen"] = false
	st.start(ctx)
	t.eq(st.current_state(), "hunting/search", "subtree conditions fall through")
	st.send_event("done")
	st.tick(0.1, ctx)
	t.eq(st.tree_status, StateTree.Status.SUCCEEDED, "subtree transition can end the whole tree")


func _run_validation(t) -> void:
	t.current = "state tree validation"
	var st := _tree()
	t.check(st.validate(_basic_asset()).is_empty(), "good asset has no errors")
	t.check(not st.validate({}).is_empty(), "empty asset rejected")
	t.check(not st.validate({"root": "x", "states": {"a": {}}}).is_empty(), "missing root state rejected")
	var errs := st.validate({"root": "a", "states": {"a": {"children": ["ghost"]}}})
	t.check(not errs.is_empty() and errs[0].contains("ghost"), "unknown child reported")
	errs = st.validate({"root": "a", "states": {"a": {"tasks": ["rm_rf"]}}})
	t.check(not errs.is_empty() and errs[0].contains("rm_rf"), "unregistered task rejected by whitelist")
	errs = st.validate({"root": "a", "states": {"a": {"conditions": ["nope"]}}})
	t.check(not errs.is_empty(), "unregistered condition rejected")
	errs = st.validate({"root": "a", "states": {"a": {"transitions": [{"trigger": "on_whim", "target": "a"}]}}})
	t.check(not errs.is_empty(), "invalid trigger rejected")
	errs = st.validate({"root": "a", "states": {"a": {"transitions": [{"trigger": "on_event", "target": "a"}]}}})
	t.check(not errs.is_empty(), "on_event without event name rejected")
	errs = st.validate({"root": "a", "states": {"a": {"transitions": [{"trigger": "on_tick", "target": "zzz"}]}}})
	t.check(not errs.is_empty(), "unknown transition target rejected")
	errs = st.validate({"root": "a", "states": {"a": {"children": ["b"]}, "b": {"children": ["a"]}}})
	t.check(not errs.is_empty(), "hierarchy cycle rejected")
	errs = st.validate({"root": "a", "states": {"a": {"link": "missing"}}})
	t.check(not errs.is_empty(), "unknown link rejected")
	st.register_subtree("loop", {"root": "x", "states": {"x": {"link": "loop"}}})
	errs = st.validate({"root": "a", "states": {"a": {"link": "loop"}}})
	t.check(not errs.is_empty(), "recursive link rejected")
	t.check(not st.set_asset({"root": "q", "states": {}}), "set_asset refuses invalid asset")
	t.check(not st.errors.is_empty(), "set_asset exposes errors")
	t.check(not st.start({}), "tree without installed asset does not start")


func _object(id: String, pos: Vector3, tags: Array, behavior: String = "sit", slots: int = 2) -> Dictionary:
	var arr: Array = []
	for i in slots:
		arr.append({"offset": Vector3(float(i) * 0.5, 0, 0), "behavior": behavior, "tags": ["seat"]})
	return {"id": id, "position": pos, "tags": tags, "slots": arr}


func _run_smart_objects(t) -> void:
	t.current = "smart object find"
	var so := SmartObjects.new()
	t.check(so.register_object(_object("bench_near", Vector3(2, 0, 0), ["public"])), "register")
	so.register_object(_object("bench_far", Vector3(20, 0, 0), ["public", "shade"]))
	so.register_object(_object("fire", Vector3(3, 0, 0), ["warm"], "warm_up", 1))
	t.check(not so.register_object({"id": "bad"}), "object without position rejected")
	var q: Dictionary = {"position": Vector3.ZERO, "radius": 30.0, "behavior": "sit"}
	var res := so.find(q)
	t.eq(res.size(), 4, "all sit slots in radius found")
	t.eq(res[0]["object"], "bench_near", "closest ranked first")
	q["radius"] = 10.0
	t.eq(so.find(q).size(), 2, "radius filters")
	q["radius"] = 30.0
	q["required_tags"] = ["shade"]
	res = so.find(q)
	t.check(res.size() == 2 and res[0]["object"] == "bench_far", "required tags filter by object tags")
	q["required_tags"] = []
	q["preferred_tags"] = ["shade"]
	res = so.find(q)
	t.eq(res[0]["object"], "bench_far", "preferred tag outweighs distance")
	t.eq(so.find({"position": Vector3.ZERO, "radius": 30.0, "behavior": "warm_up"}).size(), 1, "behavior filter")

	t.current = "smart object claims"
	var h1 := so.claim("bench_near", 0, "npc1")
	t.check(h1 > 0, "claim returns handle")
	t.eq(so.claim("bench_near", 0, "npc2"), 0, "slot claim is exclusive")
	t.check(so.claim("bench_near", 1, "npc2") > 0, "other slot claimable")
	t.eq(so.claim("bench_near", 9, "npc3"), 0, "bad slot index fails")
	t.eq(so.claim("ghost", 0, "npc3"), 0, "unknown object fails")
	q = {"position": Vector3.ZERO, "radius": 10.0, "behavior": "sit"}
	t.eq(so.find(q).size(), 0, "claimed slots hidden from find")
	q["include_claimed"] = true
	t.eq(so.find(q).size(), 2, "include_claimed shows them")
	t.eq(so.claim_user(h1), "npc1", "claim remembers user")
	t.check(so.release(h1), "release")
	t.check(not so.release(h1), "double release is a no-op")
	t.check(so.claim("bench_near", 0, "npc3") > 0, "released slot is claimable again")

	var short := so.claim("bench_far", 0, "npc4", 1.0)
	so.advance(0.6)
	t.check(so.is_claimed(short), "claim alive before timeout")
	so.touch(short)
	so.advance(0.6)
	t.check(so.is_claimed(short), "touch resets timeout")
	so.advance(0.6)
	t.check(not so.is_claimed(short), "idle claim auto-released after timeout")
	t.check(so.is_slot_free("bench_far", 0), "timed-out slot is free")
	var forever := so.claim("bench_far", 1, "npc5", 0.0)
	so.advance(1000.0)
	t.check(so.is_claimed(forever), "zero timeout never expires")
	so.unregister_object("bench_far")
	t.check(not so.is_claimed(forever), "removing object drops its claims")

	t.current = "smart object placement"
	var area := Rect2(0, 0, 40, 40)
	var reach := func(p: Vector3) -> bool: return p.x < 20.0 or p.z > 30.0
	var rules: Dictionary = {"min_spacing": 4.0, "density": 2.0, "nav_reachable": reach, "candidates": 12}
	var a := SmartObjects.new().auto_place(area, 12, rules, 1234)
	var b := SmartObjects.new().auto_place(area, 12, rules, 1234)
	t.eq(a, b, "same seed gives identical placement")
	t.check(a != SmartObjects.new().auto_place(area, 12, rules, 99), "different seed differs")
	t.check(a.size() > 5, "placed a reasonable number")
	var spacing_ok := true
	var reach_ok := true
	var inside := true
	for i in a.size():
		var p: Vector3 = a[i]
		reach_ok = reach_ok and reach.call(p)
		inside = inside and area.has_point(Vector2(p.x, p.z))
		for j in range(i + 1, a.size()):
			var other: Vector3 = a[j]
			if p.distance_to(other) < 4.0:
				spacing_ok = false
	t.check(spacing_ok, "placements respect min spacing")
	t.check(reach_ok, "placements respect nav reachability")
	t.check(inside, "placements stay inside the area")
	var all_unreachable := func(_p: Vector3) -> bool: return false
	t.eq(SmartObjects.new().auto_place(area, 5, {"nav_reachable": all_unreachable}, 1).size(), 0, "nothing reachable places nothing")
	var s := SmartObjects.new()
	t.eq(s.placement_score(Vector3.ZERO, all_unreachable, 2.0), 0.0, "unreachable scores zero")
	t.eq(s.placement_score(Vector3.ZERO, Callable(), 2.0, [Vector3(1, 0, 0)], 4.0), 0.0, "too close scores zero")
	var open_score := s.placement_score(Vector3.ZERO, Callable(), 1.0, [], 4.0)
	var crowded := s.placement_score(Vector3.ZERO, Callable(), 1.0, [Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 6)], 4.0)
	t.check(open_score > crowded and crowded > 0.0, "crowding lowers score but keeps it positive")


func _run_interactions(t) -> void:
	t.current = "smart object interactions"
	var so := SmartObjects.new()
	var effects: Array[String] = []
	so.on_effect = func(effect: String, user: Variant, obj: String) -> void:
		effects.append("%s:%s:%s" % [effect, str(user), obj])
	so.register_behavior("sit", [
		{"anim": "sit_down", "duration": 1.0, "effect": ""},
		{"anim": "sit_idle", "duration": 2.0, "effect": "heal"},
		{"anim": "stand_up", "duration": 0.5},
	])
	so.register_object(_object("bench", Vector3.ZERO, [], "sit", 1))
	var h := so.claim("bench", 0, "npc")
	t.check(not so.start_interaction(0), "invalid handle cannot start")
	t.check(so.start_interaction(h), "interaction starts")
	t.eq(so.interaction_state(h)["anim"], "sit_down", "first step active")
	so.advance(0.4)
	t.near(float(so.interaction_state(h)["t"]), 0.4, 0.0001, "step time progresses")
	so.advance(0.7)
	t.eq(so.interaction_state(h)["anim"], "sit_idle", "moves to the next step on overrun")
	t.eq(effects, ["heal:npc:bench"], "step effect fires once on entering the step")
	var done := so.advance(2.0)
	t.eq(so.interaction_state(h)["anim"], "stand_up", "last step reached")
	t.eq(done.size(), 0, "not finished yet")
	done = so.advance(5.0)
	t.eq(done, [h], "finished handle reported")
	t.check(not so.is_claimed(h), "claim released after completion")
	t.check(so.is_slot_free("bench", 0), "slot free after completion")
	t.eq(effects.size(), 1, "effect not re-fired")

	so.release_on_complete = false
	var h2 := so.claim("bench", 0, "npc2", 0.0)
	so.start_interaction(h2)
	so.advance(100.0)
	t.check(so.is_claimed(h2), "claim kept when release_on_complete is off")
	var h3 := so.claim("bench", 0, "x")
	t.eq(h3, 0, "slot still held")
	so.register_object({"id": "plain", "position": Vector3.ZERO, "slots": [{"behavior": "unknown"}]})
	var h4 := so.claim("plain", 0, "npc")
	t.check(not so.start_interaction(h4), "behavior without steps cannot start")
