extends RefCounted
## Visual script runtime: events, flow, loops, math, whitelisted calls, delay, RPC outbox,
## state machines, validation, budget, debugger hooks and serialization.

const Graph = preload("res://scripts/shared/visual_script_graph.gd")
const Library = preload("res://scripts/shared/visual_script_library.gd")


func _asset(nodes: Dictionary, exec: Array, data: Array = [], variables: Dictionary = {}) -> Dictionary:
	return {"variables": variables, "nodes": nodes, "exec": exec, "data": data}


func _print(text: String) -> Dictionary:
	return {"type": "print", "in": {"text": text}}


func _load(asset: Dictionary) -> Graph:
	var g := Graph.new()
	g.register_function("double", func(x: Variant) -> Variant: return x * 2, 1)
	var errs: Array[String] = g.load_graph(asset)
	if not errs.is_empty():
		push_error("test graph invalid: %s" % str(errs))
	return g


func _math_result(op: String, a: Variant, b: Variant, c: Variant = null, cmp: String = "==") -> Variant:
	var math: Dictionary = {"type": "math", "op": op, "cmp": cmp, "in": {"a": a, "b": b}}
	if c != null:
		math["in"]["c"] = c
	var g := _load(_asset(
		{"e": {"type": "event", "event": "go"}, "s": {"type": "set_var", "var": "r"}, "m": math},
		[["e", "out", "s"]], [["m", "result", "s", "value"]], {"r": null}))
	g.fire("go")
	return g.get_var("r")


func run(t) -> void:
	t.current = "event firing order"
	var g := _load(_asset(
		{"e1": {"type": "event", "event": "on_begin"}, "e2": {"type": "event", "event": "on_begin"},
		"a": _print("A"), "b": _print("B"), "c": _print("C"), "other": {"type": "event", "event": "nope"}},
		[["e1", "out", "a"], ["a", "out", "b"], ["e2", "out", "c"]]))
	t.eq(g.fire("on_begin"), 2, "two handlers for one event")
	t.eq(g.print_log, ["A", "B", "C"] as Array[String], "handlers run in graph order, chains in link order")
	t.eq(g.fire("unknown_event"), 0, "unknown event runs nothing")
	t.eq(Graph.new().fire("x"), 0, "firing without a graph is harmless")

	t.current = "branch and sequence"
	g = _load(_asset(
		{"e": {"type": "event", "event": "on_damage", "outputs": ["amount"]},
		"cmp": {"type": "math", "op": "compare", "cmp": ">", "in": {"b": 10}},
		"br": {"type": "branch"}, "big": _print("big"), "small": _print("small"),
		"seq": {"type": "sequence", "count": 3}, "s0": _print("0"), "s1": _print("1"), "s2": _print("2")},
		[["e", "out", "br"], ["br", "true", "big"], ["br", "false", "small"], ["big", "out", "seq"],
		["seq", "0", "s0"], ["seq", "1", "s1"], ["seq", "2", "s2"]],
		[["e", "amount", "cmp", "a"], ["cmp", "result", "br", "cond"]]))
	g.fire("on_damage", {"amount": 5})
	t.eq(g.print_log, ["small"] as Array[String], "false branch taken")
	g.print_log.clear()
	g.fire("on_damage", {"amount": 50})
	t.eq(g.print_log, ["big", "0", "1", "2"] as Array[String], "true branch then sequence in order")

	t.current = "loops and guard"
	var loop_nodes: Dictionary = {
		"e": {"type": "event", "event": "go"},
		"loop": {"type": "for_loop", "in": {"first": 0, "last": 4}},
		"gv": {"type": "get_var", "var": "total"}, "add": {"type": "math", "op": "add"},
		"sv": {"type": "set_var", "var": "total"}, "after": _print("done")}
	var loop_exec: Array = [["e", "out", "loop"], ["loop", "body", "sv"], ["loop", "done", "after"]]
	var loop_data: Array = [["gv", "value", "add", "a"], ["loop", "index", "add", "b"], ["add", "result", "sv", "value"]]
	g = _load(_asset(loop_nodes, loop_exec, loop_data, {"total": 0}))
	g.fire("go")
	t.eq(g.get_var("total"), 10, "for_loop index 0..4 summed")
	t.eq(g.print_log, ["done"] as Array[String], "done pin runs after loop")
	loop_nodes["loop"] = {"type": "for_loop", "max_iter": 3, "in": {"first": 0, "last": 1000000}}
	g = _load(_asset(loop_nodes, loop_exec, loop_data, {"total": 0}))
	g.fire("go")
	t.eq(g.get_var("total"), 3, "max_iter guard stops the loop (0+1+2)")
	t.check(g.errors.size() == 1 and "loop guard" in g.errors[0], "guard hit is reported")
	t.eq(g.print_log, ["done"] as Array[String], "graph continues after a guarded loop")

	var while_nodes: Dictionary = {
		"e": {"type": "event", "event": "go"}, "w": {"type": "while"},
		"lt": {"type": "math", "op": "compare", "cmp": "<", "in": {"b": 3}},
		"gv": {"type": "get_var", "var": "n"}, "add": {"type": "math", "op": "add", "in": {"b": 1}}, "sv": {"type": "set_var", "var": "n"}}
	var while_exec: Array = [["e", "out", "w"], ["w", "body", "sv"]]
	var while_data: Array = [["gv", "value", "lt", "a"], ["lt", "result", "w", "cond"], ["gv", "value", "add", "a"], ["add", "result", "sv", "value"]]
	g = _load(_asset(while_nodes, while_exec, while_data, {"n": 0}))
	g.fire("go")
	t.eq(g.get_var("n"), 3, "while runs until the condition fails")
	t.eq(g.errors.size(), 0, "terminating while is clean")
	while_nodes["w"] = {"type": "while", "in": {"cond": true}}
	g = _load(_asset(while_nodes, while_exec, [["gv", "value", "add", "a"], ["add", "result", "sv", "value"]], {"n": 0}))
	g.fire("go")
	t.eq(g.get_var("n"), Graph.DEFAULT_LOOP_GUARD, "while(true) stops at the default loop guard")
	t.check(not g.errors.is_empty() and "loop guard" in g.errors[0], "while guard reported")

	t.current = "instruction budget"
	while_nodes["w"] = {"type": "while", "max_iter": 100000000, "in": {"cond": true}}
	g = _load(_asset(while_nodes, while_exec, [["gv", "value", "add", "a"], ["add", "result", "sv", "value"]], {"n": 0}))
	g.fire("go")
	t.check(g.budget_exceeded, "infinite loop trips the budget")
	t.check(int(g.get_var("n")) > 100 and int(g.get_var("n")) < 10000, "work done is bounded by the budget")
	t.check("budget" in g.errors[g.errors.size() - 1], "budget error recorded")
	g.errors.clear()
	g.instruction_budget = 50
	g.fire("go")
	t.check(g.budget_exceeded, "budget is configurable")
	g = _load(_asset(
		{"e": {"type": "event", "event": "go"}, "w": {"type": "while", "max_iter": 5, "in": {"cond": true}}},
		[["e", "out", "w"], ["w", "done", "w"]]))
	g.fire("go")
	t.check(g.budget_exceeded, "exec cycle through a loop node is stopped by the budget")
	g.instruction_budget = 100
	g.budget_exceeded = false
	g.errors.clear()
	g = _load(_asset({"e": {"type": "event", "event": "go"}, "p": _print("x")}, [["e", "out", "p"]]))
	g.fire("go")
	t.check(not g.budget_exceeded and g.last_fire_instructions == 2, "normal fire costs two instructions")

	t.current = "variables"
	g = _load(_asset(
		{"e": {"type": "event", "event": "go"}, "sv": {"type": "set_var", "var": "hp", "in": {"value": 42}},
		"gv": {"type": "get_var", "var": "hp"}, "p": {"type": "print"}},
		[["e", "out", "sv"], ["sv", "out", "p"]], [["gv", "value", "p", "text"]], {"hp": 100}))
	t.eq(g.get_var("hp"), 100, "initial value")
	g.fire("go")
	t.eq(g.get_var("hp"), 42, "set_var writes")
	t.eq(g.print_log, ["42"] as Array[String], "get_var feeds data pin")
	g.set_var("hp", 7)
	t.eq(g.get_var("hp"), 7, "host set_var")
	t.eq(g.get_var("missing", "dflt"), "dflt", "get_var default")

	t.current = "math"
	t.eq(_math_result("add", 2, 3), 5, "add ints")
	t.near(float(_math_result("add", 0.5, 0.25)), 0.75, 0.0001, "add floats")
	t.eq(_math_result("sub", 2, 3), -1, "sub")
	t.eq(_math_result("mul", 4, 3), 12, "mul")
	t.near(float(_math_result("div", 7, 2)), 3.5, 0.0001, "div is float")
	t.eq(_math_result("min", 4, 3), 3, "min")
	t.eq(_math_result("max", 4, 3), 4, "max")
	t.eq(_math_result("clamp", 15, 0, 10), 10, "clamp high")
	t.eq(_math_result("clamp", -5, 0, 10), 0, "clamp low")
	t.eq(_math_result("compare", 3, 3, null, ">="), true, "compare >=")
	t.eq(_math_result("compare", 3, 3, null, "<"), false, "compare <")
	t.eq(_math_result("compare", "a", "a"), true, "compare strings")
	t.eq(_math_result("and", true, false), false, "and")
	t.eq(_math_result("or", true, false), true, "or")
	t.eq(_math_result("not", false, 0), true, "not")
	t.eq(_math_result("add", "hp ", 5), "hp 5", "add concatenates strings")
	t.near(float(_math_result("div", 1, 0)), 0.0, 0.0001, "division by zero yields 0, no crash")
	t.eq(_math_result("mul", "x", 2), 0, "non-numeric math yields 0, no crash")

	t.current = "whitelisted calls"
	var call_asset: Dictionary = _asset(
		{"e": {"type": "event", "event": "go"}, "c": {"type": "call", "fn": "double", "args": 1, "in": {"arg0": 21}},
		"sv": {"type": "set_var", "var": "r"}},
		[["e", "out", "c"], ["c", "out", "sv"]], [["c", "result", "sv", "value"]], {"r": 0})
	g = _load(call_asset)
	g.fire("go")
	t.eq(g.get_var("r"), 42, "registered function is called")
	var strict := Graph.new()
	t.check(not strict.register_function("bad", func(a: Variant, b: Variant) -> Variant: return a, 1).is_empty(), "argc mismatch rejected at registration")
	t.check(not strict.register_function("", func() -> void: pass, 0).is_empty(), "empty name rejected")
	t.check(strict.register_function("ok", func(a: Variant) -> Variant: return a, 1).is_empty(), "matching argc accepted")
	var errs: Array[String] = strict.load_graph(_asset(
		{"e": {"type": "event", "event": "go"}, "c": {"type": "call", "fn": "call", "args": 0}}, [["e", "out", "c"]]))
	t.check(errs.size() == 1 and "not whitelisted" in errs[0], "arbitrary call is not whitelisted")
	errs = strict.load_graph(_asset(
		{"e": {"type": "event", "event": "go"}, "c": {"type": "call", "fn": "ok", "args": 2}}, [["e", "out", "c"]]))
	t.check(errs.size() == 1 and "takes 1 args" in errs[0], "node arg count must match the function")
	g = _load(call_asset)
	g.unregister_function("double")
	g.fire("go")
	t.eq(g.get_var("r"), null, "unknown function at runtime yields null, not a crash")
	t.check(not g.errors.is_empty() and "unknown function" in g.errors[0], "runtime unknown function reported")

	t.current = "default library"
	var lib := Library.new(7)
	g = Graph.new()
	t.eq(lib.install(g).size(), 0, "library installs cleanly")
	t.check(g.has_function("random_range") and g.has_function("spawn_effect") and g.has_function("distance"), "functions whitelisted")
	errs = g.load_graph(_asset(
		{"e": {"type": "event", "event": "go"},
		"d": {"type": "call", "fn": "distance", "args": 2, "in": {"arg0": Vector3(0, 0, 0), "arg1": Vector3(3, 4, 0)}},
		"f": {"type": "call", "fn": "format", "args": 2, "in": {"arg0": "dist {}"}},
		"fx": {"type": "call", "fn": "spawn_effect", "args": 2, "in": {"arg0": "blood", "arg1": Vector3(1, 2, 3)}},
		"r": {"type": "call", "fn": "random_range", "args": 2, "in": {"arg0": 5, "arg1": 6}},
		"sv": {"type": "set_var", "var": "out"}, "sr": {"type": "set_var", "var": "rnd"}},
		[["e", "out", "d"], ["d", "out", "f"], ["f", "out", "fx"], ["fx", "out", "r"], ["r", "out", "sv"], ["sv", "out", "sr"]],
		[["d", "result", "f", "arg1"], ["f", "result", "sv", "value"], ["r", "result", "sr", "value"]], {"out": "", "rnd": 0.0}))
	t.eq(errs.size(), 0, "library graph validates")
	g.fire("go")
	t.eq(g.get_var("out"), "dist 5.0", "distance + format")
	t.check(float(g.get_var("rnd")) >= 5.0 and float(g.get_var("rnd")) <= 6.0, "random_range in range")
	t.eq(lib.effects.size(), 1, "spawn_effect only records the request")
	t.eq(lib.effects[0]["effect"], "blood", "effect name recorded")
	t.eq(lib.distance("x", 1), -1.0, "bad distance args are neutral")
	t.check(not lib.errors.is_empty(), "bad library args are logged")
	t.check(not Library.register_host(g, "Bad-Name", func() -> void: pass, 0).is_empty(), "host function names are validated")
	t.check(Library.register_host(g, "host_fn", func(a: Variant) -> Variant: return a, 1).is_empty(), "host function registered")
	t.check(not Library.register_host(g, "host_fn2", func(a: Variant) -> Variant: return a, 3).is_empty(), "host function argc checked")

	t.current = "delay"
	g = _load(_asset(
		{"e": {"type": "event", "event": "go", "outputs": ["who"]}, "a": _print("before"),
		"d": {"type": "delay", "in": {"seconds": 1.0}}, "b": {"type": "print"}},
		[["e", "out", "a"], ["a", "out", "d"], ["d", "out", "b"]], [["e", "who", "b", "text"]]))
	g.fire("go", {"who": "bob"})
	t.eq(g.print_log, ["before"] as Array[String], "nothing after the delay yet")
	t.eq(g.pending_count(), 1, "continuation scheduled")
	g.tick(0.5)
	t.eq(g.print_log.size(), 1, "not due after 0.5s")
	g.tick(0.6)
	t.eq(g.print_log, ["before", "bob"] as Array[String], "continuation runs with the original payload")
	t.eq(g.pending_count(), 0, "continuation consumed")
	g.tick(5.0)
	t.eq(g.print_log.size(), 2, "does not run twice")

	t.current = "rpc outbox"
	g = _load(_asset(
		{"e": {"type": "event", "event": "on_attack", "outputs": ["target"]},
		"r": {"type": "emit_rpc", "rpc": "request_attack", "args": 2, "in": {"arg1": 25}}},
		[["e", "out", "r"]], [["e", "target", "r", "arg0"]]))
	g.fire("on_attack", {"target": "npc_7"})
	g.fire("on_attack", {"target": "npc_9"})
	var sent: Array[Dictionary] = g.drain_outbox()
	t.eq(sent.size(), 2, "two requests recorded")
	t.eq(sent[0]["name"], "request_attack", "rpc name")
	t.eq(sent[0]["args"], ["npc_7", 25] as Array, "rpc args carry data pins and constants")
	t.eq(sent[1]["args"][0], "npc_9", "second request")
	t.eq(g.outbox.size(), 0, "drain empties the outbox")

	t.current = "state machine"
	var sm_asset: Dictionary = _asset(
		{"alert": {"type": "event", "event": "on_alert"},
		"tr": {"type": "state_transition", "machine": "ai", "from": "idle", "to": "chase"},
		"ok": _print("chasing"), "no": _print("ignored"),
		"entered": {"type": "event", "event": "on_enter_chase", "outputs": ["from"]},
		"pe": {"type": "print"},
		"st": {"type": "get_state", "machine": "ai"}, "pst": {"type": "print"},
		"reset": {"type": "event", "event": "reset"},
		"enter": {"type": "state_enter", "machine": "ai", "state": "idle"}},
		[["alert", "out", "tr"], ["tr", "out", "ok"], ["tr", "blocked", "no"], ["ok", "out", "pst"],
		["entered", "out", "pe"], ["reset", "out", "enter"]],
		[["entered", "from", "pe", "text"], ["st", "state", "pst", "text"]],
		{})
	sm_asset["machines"] = {"ai": {"initial": "idle"}}
	g = _load(sm_asset)
	t.eq(g.get_state("ai"), "idle", "initial state")
	g.fire("on_alert")
	t.eq(g.get_state("ai"), "chase", "transition taken from matching state")
	t.eq(g.print_log, ["chasing", "chase", "idle"] as Array[String], "out pin ran, then on_enter event saw the old state")
	g.print_log.clear()
	g.fire("on_alert")
	t.eq(g.print_log, ["ignored"] as Array[String], "blocked pin when state does not match")
	g.fire("reset")
	t.eq(g.get_state("ai"), "idle", "state_enter sets state directly")
	t.eq(g.transitions, ["ai:idle->chase", "ai:chase->idle"] as Array[String], "transition log")

	t.current = "validation"
	var v := Graph.new()
	errs = v.load_graph(_asset({"x": {"type": "teleport"}}, []))
	t.check(errs.size() == 1 and "unknown type" in errs[0], "unknown node type")
	t.check(not v.is_loaded(), "invalid graph is not installed")
	errs = v.load_graph(_asset({"e": {"type": "event", "event": "go"}}, [["e", "out", "ghost"]]))
	t.check(errs.size() == 1 and "dangling" in errs[0], "dangling exec target")
	errs = v.load_graph(_asset({"e": {"type": "event", "event": "go"}, "p": _print("x")}, [["e", "out", "p"]], [["ghost", "value", "p", "text"]]))
	t.check(errs.size() == 1 and "dangling" in errs[0], "dangling data source")
	errs = v.load_graph(_asset({"e": {"type": "event", "event": "go"}, "p": _print("x")}, [["e", "nope", "p"]]))
	t.check(errs.size() == 1 and "no exec pin" in errs[0], "unknown exec pin")
	errs = v.load_graph(_asset({"e": {"type": "event", "event": "go"}, "l": {"type": "literal", "value_type": "int", "value": "text"}}, []))
	t.check(errs.size() == 1 and "does not match" in errs[0], "literal type mismatch")
	errs = v.load_graph(_asset({"l": {"type": "literal", "value_type": "float", "value": 3}}, []))
	t.eq(errs.size(), 0, "int literal is a valid float")
	errs = v.load_graph(_asset({"g": {"type": "get_var", "var": "ghost"}}, []))
	t.check(errs.size() == 1 and "unknown variable" in errs[0], "undeclared variable")
	errs = v.load_graph(_asset({"m": {"type": "math", "op": "pow"}}, []))
	t.check(errs.size() == 1 and "unknown math op" in errs[0], "unknown math op")
	errs = v.load_graph(_asset({"e": {"type": "event", "event": "go"}, "g": {"type": "get_var", "var": "a"}}, [["e", "out", "g"]], [], {"a": 1}))
	t.check(errs.size() == 1 and "not executable" in errs[0], "pure node cannot be an exec target")
	errs = v.load_graph(_asset(
		{"e": {"type": "event", "event": "go"}, "a": _print("a"), "b": _print("b")},
		[["e", "out", "a"], ["a", "out", "b"], ["b", "out", "a"]]))
	t.check(errs.size() == 1 and "cycle without loop" in errs[0], "exec cycle without a loop node")
	errs = v.load_graph(_asset(
		{"e": {"type": "event", "event": "go"}, "a": _print("a"), "d": {"type": "delay", "in": {"seconds": 1.0}}},
		[["e", "out", "a"], ["a", "out", "d"], ["d", "out", "a"]]))
	t.eq(errs.size(), 0, "a cycle through a delay is a legitimate timer")
	errs = v.load_graph(_asset({"e": {"type": "event", "event": "go", "outputs": ["x"]}, "p": _print("x")}, [["e", "out", "p"]], [["e", "y", "p", "text"]]))
	t.check(errs.size() == 1 and "no data output" in errs[0], "unknown data output pin")

	t.current = "debugger"
	g = _load(_asset(
		{"e": {"type": "event", "event": "go"}, "a": _print("A"), "b": _print("B"), "c": _print("C")},
		[["e", "out", "a"], ["a", "out", "b"], ["b", "out", "c"]]))
	g.trace_enabled = true
	g.fire("go")
	t.eq(g.trace, ["e", "a", "b", "c"] as Array[String], "trace lists executed node ids in order")
	g.clear_trace()
	var hits: Array[String] = []
	g.break_handler = func(id: String) -> void: hits.append(id)
	g.set_breakpoint("b")
	g.fire("go")
	t.eq(g.breakpoint_hits, ["b"] as Array[String], "breakpoint recorded")
	t.eq(hits, ["b"] as Array[String], "break handler invoked")
	g.set_breakpoint("b", false)
	g.clear_trace()
	g.fire("go")
	t.eq(g.breakpoint_hits.size(), 0, "breakpoint removed")

	t.current = "serialization"
	g = _load(_asset(
		{"e": {"type": "event", "event": "go", "outputs": ["n"]}, "sv": {"type": "set_var", "var": "last"},
		"c": {"type": "call", "fn": "double", "args": 1}},
		[["e", "out", "c"], ["c", "out", "sv"]], [["e", "n", "c", "arg0"], ["c", "result", "sv", "value"]], {"last": 0}))
	g.fire("go", {"n": 4})
	var saved: Dictionary = g.to_dict()
	t.eq(saved["variables"]["last"], 8, "to_dict captures current variables")
	var h := Graph.new()
	h.register_function("double", func(x: Variant) -> Variant: return x * 2, 1)
	t.eq(h.load_graph(saved).size(), 0, "saved asset reloads")
	t.eq(h.get_var("last"), 8, "variables restored")
	h.fire("go", {"n": 10})
	t.eq(h.get_var("last"), 20, "reloaded graph behaves the same")
	t.eq(h.to_dict()["nodes"], saved["nodes"], "nodes survive the round trip")
	t.eq(h.to_dict()["exec"], saved["exec"], "exec links survive")
	t.eq(h.to_dict()["data"], saved["data"], "data links survive")
	var copy: Dictionary = saved.duplicate(true)
	copy["nodes"]["e"]["event"] = "changed"
	t.eq(g.to_dict()["nodes"]["e"]["event"], "go", "to_dict returns an independent copy")
