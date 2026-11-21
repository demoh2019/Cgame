extends RefCounted
## Blueprint-style visual script runtime: event graph with execution pins and
## data pins, for gameplay logic, gameplay state graphs and RPC graphs.
##
## Design credit (concepts only, no code copied): the exec-pin / data-pin split and
## pull-evaluated pure nodes follow the general dataflow model described for Unreal
## Blueprints (Epic documentation, concepts are not copyrightable); the typed-node
## sequence/branch/loop/event vocabulary follows Godot 3 VisualScript design notes
## (Godot Engine, MIT licence); flow-based programming is J. P. Morrison's public
## model. Implementation is original GDScript. No Apache-2.0/GPL/LGPL code ported.
##
## Asset format:
##   {"variables": {name: initial}, "machines": {name: {"initial": state}},
##    "nodes": {id: {"type": ..., ...}},
##    "exec": [[from_id, from_pin, to_id]],
##    "data": [[from_id, from_out, to_id, to_in]]}
##
## Node types and pins:
##   event            "event": name, "outputs": [payload keys]; exec out "out"; data outs = payload keys
##   branch           in "cond"; exec "true" / "false"
##   sequence         "count": n; exec "0".."n-1"
##   for_loop         ins "first","last" (inclusive), "max_iter"; exec "body","done"; data out "index"
##   while            in "cond", "max_iter"; exec "body","done"
##   set_var          "var"; in "value"; exec "out"
##   get_var          "var"; data out "value"
##   literal          "value", optional "value_type": int|float|string|bool; data out "value"
##   math             "op": add sub mul div min max clamp compare and or not, "cmp" for compare;
##                    ins "a","b","c"; data out "result"
##   call             "fn": whitelisted host function, "args": n; ins "arg0".."argN"; out "result"
##   delay            in "seconds"; exec "out" fires from tick(delta)
##   print            in "text"; exec "out"
##   emit_rpc         "rpc": name, "args": n; ins "arg0".."argN"; records into the outbox only
##   state_enter      "machine","state"; exec "out"
##   state_transition "machine","from" ("*" = any),"to"; exec "out" / "blocked"
##   get_state        "machine"; data out "state"
## Unlinked data inputs read constants from the node's "in" dictionary.

const NODE_TYPES: Array[String] = [
	"event", "branch", "sequence", "for_loop", "while", "set_var", "get_var", "literal",
	"math", "call", "delay", "print", "emit_rpc", "state_enter", "state_transition", "get_state",
]
const PURE_TYPES: Array[String] = ["get_var", "literal", "math", "get_state"]
const MATH_OPS: Array[String] = ["add", "sub", "mul", "div", "min", "max", "clamp", "compare", "and", "or", "not"]
const CMP_OPS: Array[String] = ["==", "!=", "<", "<=", ">", ">="]
const LOOP_TYPES: Array[String] = ["for_loop", "while", "delay"]
const DEFAULT_LOOP_GUARD := 1000
const MAX_DEPTH := 64
const MAX_LOG := 1000
const MAX_ERRORS := 100

## Instruction budget per fire() / delay continuation; stops runaway graphs.
var instruction_budget: int = 10000
var budget_exceeded: bool = false
var last_fire_instructions: int = 0

var trace_enabled: bool = false
var trace: Array[String] = []
var trace_limit: int = 5000
var breakpoints: Dictionary = {}
var breakpoint_hits: Array[String] = []
## Optional debugger hook: called as break_handler.call(node_id) when a breakpoint node runs.
var break_handler: Callable = Callable()

var print_log: Array[String] = []
var errors: Array[String] = []
var outbox: Array[Dictionary] = []
var transitions: Array[String] = []

var _asset: Dictionary = {}
var _nodes: Dictionary = {}
var _exec_out: Dictionary = {}
var _data_in: Dictionary = {}
var _events: Dictionary = {}
var _vars: Dictionary = {}
var _machines: Dictionary = {}
var _functions: Dictionary = {}
var _pending: Array[Dictionary] = []
var _queue: Array = []
var _loaded: bool = false
var _budget_left: int = 0
var _halted: bool = false
var _depth: int = 0
var _pure_depth: int = 0
var _fire_depth: int = 0
var _seq: int = 0


# ---------------------------------------------------------------- function whitelist

## Registers a host function. argc must match the callable's argument count (-1 skips the check).
## Returns an error string, or "" on success.
func register_function(fn_name: String, callable: Callable, argc: int) -> String:
	if fn_name.is_empty():
		return "empty function name"
	if not callable.is_valid():
		return "function '%s': invalid callable" % fn_name
	if argc < -1:
		return "function '%s': bad argument count %d" % [fn_name, argc]
	if argc >= 0 and callable.get_argument_count() != argc:
		return "function '%s': declared %d args but callable takes %d" % [fn_name, argc, callable.get_argument_count()]
	_functions[fn_name] = {"callable": callable, "argc": argc}
	return ""


func unregister_function(fn_name: String) -> void:
	_functions.erase(fn_name)


func has_function(fn_name: String) -> bool:
	return _functions.has(fn_name)


# ---------------------------------------------------------------- validation / loading

func load_graph(asset: Dictionary) -> Array[String]:
	var errs: Array[String] = validate(asset)
	if not errs.is_empty():
		return errs
	_asset = asset.duplicate(true)
	_nodes = _dict_of(_asset.get("nodes", {}))
	_vars = _dict_of(_asset.get("variables", {}))
	_machines = {}
	var machines: Dictionary = _dict_of(_asset.get("machines", {}))
	for m in machines:
		var md: Dictionary = _dict_of(machines[m])
		_machines[str(m)] = str(md.get("initial", ""))
	_exec_out = {}
	_data_in = {}
	_events = {}
	for id_v in _nodes:
		var id: String = str(id_v)
		var n: Dictionary = _nodes[id_v]
		if str(n["type"]) == "event":
			var ename: String = str(n.get("event", ""))
			if not _events.has(ename):
				_events[ename] = []
			var lst: Array = _events[ename]
			lst.append(id)
	for e in _arr_of(_asset.get("exec", [])):
		var ea: Array = e
		var fid: String = str(ea[0])
		if not _exec_out.has(fid):
			_exec_out[fid] = {}
		var pins: Dictionary = _exec_out[fid]
		var pin: String = str(ea[1])
		if not pins.has(pin):
			pins[pin] = []
		var targets: Array = pins[pin]
		targets.append(str(ea[2]))
	for d in _arr_of(_asset.get("data", [])):
		var da: Array = d
		var tid: String = str(da[2])
		if not _data_in.has(tid):
			_data_in[tid] = {}
		var ins: Dictionary = _data_in[tid]
		ins[str(da[3])] = [str(da[0]), str(da[1])]
	_pending.clear()
	_queue.clear()
	_loaded = true
	return errs


func is_loaded() -> bool:
	return _loaded


func validate(asset: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if typeof(asset.get("nodes", {})) != TYPE_DICTIONARY:
		errs.append("nodes must be a dictionary")
		return errs
	var nodes: Dictionary = asset["nodes"] if asset.has("nodes") else {}
	var vars: Dictionary = _dict_of(asset.get("variables", {}))
	for id_v in nodes:
		var id: String = str(id_v)
		if typeof(nodes[id_v]) != TYPE_DICTIONARY:
			errs.append("node %s: not a dictionary" % id)
			continue
		var n: Dictionary = nodes[id_v]
		var ntype: String = str(n.get("type", ""))
		if not NODE_TYPES.has(ntype):
			errs.append("node %s: unknown type '%s'" % [id, ntype])
			continue
		_validate_node(id, n, ntype, vars, errs)
	var exec_adj: Dictionary = {}
	for e in _arr_of(asset.get("exec", [])):
		if typeof(e) != TYPE_ARRAY or (e as Array).size() != 3:
			errs.append("exec link must be [from, pin, to]")
			continue
		var ea: Array = e
		var fid: String = str(ea[0])
		var pin: String = str(ea[1])
		var tid: String = str(ea[2])
		if not nodes.has(fid):
			errs.append("exec link: dangling source '%s'" % fid)
			continue
		if not nodes.has(tid):
			errs.append("exec link: dangling target '%s'" % tid)
			continue
		var fn: Dictionary = nodes[fid]
		var tn: Dictionary = nodes[tid]
		var ftype: String = str(fn.get("type", ""))
		var ttype: String = str(tn.get("type", ""))
		if not NODE_TYPES.has(ftype) or not NODE_TYPES.has(ttype):
			continue
		if not _exec_pins(fn, ftype).has(pin):
			errs.append("exec link: node %s (%s) has no exec pin '%s'" % [fid, ftype, pin])
			continue
		if ttype == "event" or PURE_TYPES.has(ttype):
			errs.append("exec link: node %s (%s) is not executable" % [tid, ttype])
			continue
		if not exec_adj.has(fid):
			exec_adj[fid] = []
		var adj: Array = exec_adj[fid]
		adj.append(tid)
	for d in _arr_of(asset.get("data", [])):
		if typeof(d) != TYPE_ARRAY or (d as Array).size() != 4:
			errs.append("data link must be [from, out, to, in]")
			continue
		var da: Array = d
		var dfid: String = str(da[0])
		var dout: String = str(da[1])
		var dtid: String = str(da[2])
		var din: String = str(da[3])
		if not nodes.has(dfid):
			errs.append("data link: dangling source '%s'" % dfid)
			continue
		if not nodes.has(dtid):
			errs.append("data link: dangling target '%s'" % dtid)
			continue
		var dfn: Dictionary = nodes[dfid]
		var dtype: String = str(dfn.get("type", ""))
		if din.is_empty():
			errs.append("data link: empty input pin on '%s'" % dtid)
		if str(_dict_of(nodes[dtid]).get("type", "")) == "event":
			errs.append("data link: event node %s has no data inputs" % dtid)
		if NODE_TYPES.has(dtype) and not _data_outs(dfn, dtype).has(dout):
			errs.append("data link: node %s (%s) has no data output '%s'" % [dfid, dtype, dout])
	_check_cycles(nodes, exec_adj, errs)
	return errs


func _validate_node(id: String, n: Dictionary, ntype: String, vars: Dictionary, errs: Array[String]) -> void:
	match ntype:
		"event":
			if str(n.get("event", "")).is_empty():
				errs.append("node %s: event needs a name" % id)
		"set_var", "get_var":
			var vn: String = str(n.get("var", ""))
			if not vars.has(vn):
				errs.append("node %s: unknown variable '%s'" % [id, vn])
		"literal":
			var vt: String = str(n.get("value_type", ""))
			var v: Variant = n.get("value")
			var ok := true
			match vt:
				"": ok = true
				"int": ok = typeof(v) == TYPE_INT
				"float": ok = typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
				"string": ok = typeof(v) == TYPE_STRING
				"bool": ok = typeof(v) == TYPE_BOOL
				_:
					ok = false
					errs.append("node %s: unknown literal value_type '%s'" % [id, vt])
			if not ok and NODE_TYPES.has(ntype) and ["int", "float", "string", "bool"].has(vt):
				errs.append("node %s: literal value does not match type '%s'" % [id, vt])
		"math":
			var op: String = str(n.get("op", ""))
			if not MATH_OPS.has(op):
				errs.append("node %s: unknown math op '%s'" % [id, op])
			elif op == "compare" and not CMP_OPS.has(str(n.get("cmp", "=="))):
				errs.append("node %s: unknown compare '%s'" % [id, str(n.get("cmp", ""))])
		"call":
			var fname: String = str(n.get("fn", ""))
			if not _functions.has(fname):
				errs.append("node %s: unknown function '%s' (not whitelisted)" % [id, fname])
			else:
				var fd: Dictionary = _functions[fname]
				var argc: int = int(fd["argc"])
				if argc >= 0 and int(n.get("args", 0)) != argc:
					errs.append("node %s: function '%s' takes %d args, node declares %d" % [id, fname, argc, int(n.get("args", 0))])
		"emit_rpc":
			if str(n.get("rpc", "")).is_empty():
				errs.append("node %s: emit_rpc needs an rpc name" % id)
		"sequence":
			if int(n.get("count", 2)) < 1:
				errs.append("node %s: sequence count must be >= 1" % id)
		"for_loop", "while":
			if int(n.get("max_iter", DEFAULT_LOOP_GUARD)) < 1:
				errs.append("node %s: max_iter must be >= 1" % id)
		"state_enter":
			if str(n.get("machine", "")).is_empty() or str(n.get("state", "")).is_empty():
				errs.append("node %s: state_enter needs machine and state" % id)
		"state_transition":
			if str(n.get("machine", "")).is_empty() or str(n.get("to", "")).is_empty():
				errs.append("node %s: state_transition needs machine and to" % id)
		"get_state":
			if str(n.get("machine", "")).is_empty():
				errs.append("node %s: get_state needs machine" % id)


func _exec_pins(n: Dictionary, ntype: String) -> Array[String]:
	var pins: Array[String] = []
	match ntype:
		"event", "set_var", "call", "delay", "print", "emit_rpc", "state_enter":
			pins.append("out")
		"branch":
			pins.append_array(["true", "false"])
		"sequence":
			for i in int(n.get("count", 2)):
				pins.append(str(i))
		"for_loop", "while":
			pins.append_array(["body", "done"])
		"state_transition":
			pins.append_array(["out", "blocked"])
	return pins


func _data_outs(n: Dictionary, ntype: String) -> Array[String]:
	var outs: Array[String] = []
	match ntype:
		"event":
			for o in _arr_of(n.get("outputs", [])):
				outs.append(str(o))
		"literal", "get_var":
			outs.append("value")
		"math", "call":
			outs.append("result")
		"for_loop":
			outs.append("index")
		"get_state":
			outs.append("state")
	return outs


func _check_cycles(nodes: Dictionary, adj: Dictionary, errs: Array[String]) -> void:
	var color: Dictionary = {}
	var stack: Array[String] = []
	var reported: Dictionary = {}
	for id_v in nodes:
		var id: String = str(id_v)
		if not color.has(id):
			_dfs(id, nodes, adj, color, stack, reported, errs)


func _dfs(id: String, nodes: Dictionary, adj: Dictionary, color: Dictionary, stack: Array[String], reported: Dictionary, errs: Array[String]) -> void:
	color[id] = 1
	stack.append(id)
	var nexts: Array = _arr_of(adj.get(id, []))
	for t_v in nexts:
		var t: String = str(t_v)
		if not color.has(t):
			_dfs(t, nodes, adj, color, stack, reported, errs)
		elif int(color[t]) == 1:
			var start: int = stack.find(t)
			var has_loop := false
			var path: Array[String] = []
			for i in range(start, stack.size()):
				var cid: String = stack[i]
				path.append(cid)
				var cn: Dictionary = nodes[cid]
				if LOOP_TYPES.has(str(cn.get("type", ""))):
					has_loop = true
			var key: String = ",".join(path)
			if not has_loop and not reported.has(key):
				reported[key] = true
				errs.append("exec cycle without loop node: %s" % " -> ".join(path))
	stack.pop_back()
	color[id] = 2


# ---------------------------------------------------------------- variables / state API

func get_var(var_name: String, default_value: Variant = null) -> Variant:
	return _vars.get(var_name, default_value)


func set_var(var_name: String, value: Variant) -> void:
	_vars[var_name] = value


func get_state(machine: String) -> String:
	return str(_machines.get(machine, ""))


func pending_count() -> int:
	return _pending.size()


## Returns and clears the outgoing RPC requests. The host decides how to send them.
func drain_outbox() -> Array[Dictionary]:
	var out: Array[Dictionary] = outbox.duplicate()
	outbox.clear()
	return out


func to_dict() -> Dictionary:
	var d: Dictionary = _asset.duplicate(true)
	d["variables"] = _vars.duplicate(true)
	var machines: Dictionary = {}
	for m in _machines:
		machines[str(m)] = {"initial": str(_machines[m])}
	d["machines"] = machines
	return d


func set_breakpoint(node_id: String, enabled: bool = true) -> void:
	if enabled:
		breakpoints[node_id] = true
	else:
		breakpoints.erase(node_id)


func clear_trace() -> void:
	trace.clear()
	breakpoint_hits.clear()


# ---------------------------------------------------------------- execution

## Runs every event node named event_name. Returns the number of handlers run.
func fire(event_name: String, payload: Dictionary = {}) -> int:
	if not _loaded:
		_err("fire('%s'): no graph loaded" % event_name)
		return 0
	if _fire_depth == 0:
		budget_exceeded = false
	var ids: Array = _arr_of(_events.get(event_name, []))
	var ran := 0
	_begin_run()
	for id_v in ids:
		if _halted:
			break
		var ctx: Dictionary = {"payload": payload, "results": {}, "loops": {}}
		_exec_chain(str(id_v), ctx)
		ran += 1
	last_fire_instructions = instruction_budget - _budget_left
	_drain_queue()
	return ran


## Advances delay nodes; due continuations run with a fresh instruction budget.
func tick(delta: float) -> void:
	if _pending.is_empty():
		return
	var due: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for p_v in _pending:
		var p: Dictionary = p_v
		p["remaining"] = float(p["remaining"]) - delta
		if float(p["remaining"]) <= 0.0:
			due.append(p)
		else:
			keep.append(p)
	_pending = keep
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["remaining"]) != float(b["remaining"]):
			return float(a["remaining"]) < float(b["remaining"])
		return int(a["seq"]) < int(b["seq"]))
	for p in due:
		if _fire_depth == 0:
			budget_exceeded = false
		_begin_run()
		var ctx: Dictionary = p["ctx"]
		_run_pin(str(p["node"]), "out", ctx)
		last_fire_instructions = instruction_budget - _budget_left
		_drain_queue()


func _drain_queue() -> void:
	if _fire_depth > 0:
		return
	var rounds := 0
	while not _queue.is_empty() and rounds < 64:
		rounds += 1
		var q: Array = _queue.pop_front()
		_fire_depth += 1
		fire(str(q[0]), _dict_of(q[1]))
		_fire_depth -= 1
	_queue.clear()


func _begin_run() -> void:
	_budget_left = instruction_budget
	_halted = false
	_depth = 0
	_pure_depth = 0


func _spend() -> bool:
	if _halted:
		return false
	_budget_left -= 1
	if _budget_left < 0:
		_halted = true
		budget_exceeded = true
		_err("instruction budget exceeded (%d)" % instruction_budget)
		return false
	return true


func _err(msg: String) -> void:
	if errors.size() < MAX_ERRORS:
		errors.append(msg)


func _exec_chain(start: String, ctx: Dictionary) -> void:
	_depth += 1
	if _depth > MAX_DEPTH:
		_err("execution nested deeper than %d" % MAX_DEPTH)
		_halted = true
		_depth -= 1
		return
	var cur: String = start
	while cur != "" and not _halted:
		cur = _exec_node(cur, ctx)
	_depth -= 1


func _targets(id: String, pin: String) -> Array:
	var pins: Dictionary = _dict_of(_exec_out.get(id, {}))
	return _arr_of(pins.get(pin, []))


func _run_pin(id: String, pin: String, ctx: Dictionary) -> void:
	for t in _targets(id, pin):
		if _halted:
			return
		_exec_chain(str(t), ctx)


## Runs all but the last target of a pin and returns the last (continued by the caller's loop).
func _next(id: String, pin: String, ctx: Dictionary) -> String:
	var ts: Array = _targets(id, pin)
	if ts.is_empty():
		return ""
	for i in range(ts.size() - 1):
		if _halted:
			return ""
		_exec_chain(str(ts[i]), ctx)
	return str(ts[ts.size() - 1])


func _exec_node(id: String, ctx: Dictionary) -> String:
	if not _spend():
		return ""
	if trace_enabled and trace.size() < trace_limit:
		trace.append(id)
	if breakpoints.has(id):
		breakpoint_hits.append(id)
		if break_handler.is_valid():
			break_handler.call(id)
	var n: Dictionary = _nodes[id]
	match str(n["type"]):
		"event":
			return _next(id, "out", ctx)
		"branch":
			var cond: bool = _truthy(_pull(id, "cond", ctx, false))
			if _halted:
				return ""
			return _next(id, "true" if cond else "false", ctx)
		"sequence":
			var count: int = int(n.get("count", 2))
			for i in range(count - 1):
				_run_pin(id, str(i), ctx)
				if _halted:
					return ""
			return _next(id, str(count - 1), ctx)
		"for_loop":
			return _exec_for(id, n, ctx)
		"while":
			return _exec_while(id, n, ctx)
		"set_var":
			var val: Variant = _pull(id, "value", ctx)
			if _halted:
				return ""
			_vars[str(n.get("var", ""))] = val
			return _next(id, "out", ctx)
		"call":
			var res: Variant = _call(id, n, ctx)
			if _halted:
				return ""
			var results: Dictionary = ctx["results"]
			results[id] = res
			return _next(id, "out", ctx)
		"delay":
			var secs: float = float(_pull(id, "seconds", ctx, 0.0))
			if _halted:
				return ""
			_pending.append({"node": id, "remaining": secs, "ctx": ctx, "seq": _seq})
			_seq += 1
			return ""
		"print":
			var text: String = str(_pull(id, "text", ctx, ""))
			if _halted:
				return ""
			if print_log.size() < MAX_LOG:
				print_log.append(text)
			return _next(id, "out", ctx)
		"emit_rpc":
			var args: Array = _collect_args(id, n, ctx)
			if _halted:
				return ""
			if outbox.size() < MAX_LOG:
				outbox.append({"name": str(n.get("rpc", "")), "args": args})
			return _next(id, "out", ctx)
		"state_enter":
			_change_state(str(n.get("machine", "")), str(n.get("state", "")))
			return _next(id, "out", ctx)
		"state_transition":
			var machine: String = str(n.get("machine", ""))
			var from_state: String = str(n.get("from", "*"))
			var cur: String = get_state(machine)
			if from_state == "*" or from_state == cur:
				_change_state(machine, str(n.get("to", "")))
				return _next(id, "out", ctx)
			return _next(id, "blocked", ctx)
	return ""


func _exec_for(id: String, n: Dictionary, ctx: Dictionary) -> String:
	var first: int = int(_pull(id, "first", ctx, 0))
	var last: int = int(_pull(id, "last", ctx, 0))
	var max_iter: int = int(n.get("max_iter", DEFAULT_LOOP_GUARD))
	var loops: Dictionary = ctx["loops"]
	var i: int = first
	var count := 0
	while i <= last:
		if count >= max_iter:
			_err("loop guard: for_loop %s stopped after %d iterations" % [id, max_iter])
			break
		loops[id] = i
		_run_pin(id, "body", ctx)
		if _halted:
			return ""
		i += 1
		count += 1
	return _next(id, "done", ctx)


func _exec_while(id: String, n: Dictionary, ctx: Dictionary) -> String:
	var max_iter: int = int(n.get("max_iter", DEFAULT_LOOP_GUARD))
	var count := 0
	while _truthy(_pull(id, "cond", ctx, false)):
		if _halted:
			return ""
		if count >= max_iter:
			_err("loop guard: while %s stopped after %d iterations" % [id, max_iter])
			break
		_run_pin(id, "body", ctx)
		if _halted:
			return ""
		count += 1
	if _halted:
		return ""
	return _next(id, "done", ctx)


func _change_state(machine: String, to_state: String) -> void:
	var from_state: String = get_state(machine)
	if from_state == to_state:
		return
	_machines[machine] = to_state
	transitions.append("%s:%s->%s" % [machine, from_state, to_state])
	var payload: Dictionary = {"machine": machine, "from": from_state, "to": to_state}
	if not from_state.is_empty():
		_queue.append(["on_exit_" + from_state, payload])
	_queue.append(["on_enter_" + to_state, payload])


func _collect_args(id: String, n: Dictionary, ctx: Dictionary) -> Array:
	var args: Array = []
	for i in int(n.get("args", 0)):
		args.append(_pull(id, "arg%d" % i, ctx))
	return args


func _call(id: String, n: Dictionary, ctx: Dictionary) -> Variant:
	var fname: String = str(n.get("fn", ""))
	if not _functions.has(fname):
		_err("call: unknown function '%s'" % fname)
		return null
	var fd: Dictionary = _functions[fname]
	var callable: Callable = fd["callable"]
	var args: Array = _collect_args(id, n, ctx)
	var argc: int = int(fd["argc"])
	if argc >= 0 and args.size() != argc:
		_err("call: function '%s' takes %d args, got %d" % [fname, argc, args.size()])
		return null
	if not callable.is_valid():
		_err("call: function '%s' is no longer valid" % fname)
		return null
	return callable.callv(args)


# ---------------------------------------------------------------- data pins

func _pull(id: String, pin: String, ctx: Dictionary, default_value: Variant = null) -> Variant:
	var links: Dictionary = _dict_of(_data_in.get(id, {}))
	if links.has(pin):
		var l: Array = links[pin]
		return _out_value(str(l[0]), str(l[1]), ctx)
	var n: Dictionary = _nodes[id]
	var consts: Dictionary = _dict_of(n.get("in", {}))
	return consts.get(pin, default_value)


func _out_value(id: String, out: String, ctx: Dictionary) -> Variant:
	if not _spend():
		return null
	_pure_depth += 1
	if _pure_depth > MAX_DEPTH:
		_err("data pins nested deeper than %d" % MAX_DEPTH)
		_halted = true
		_pure_depth -= 1
		return null
	var n: Dictionary = _nodes[id]
	var result: Variant = null
	match str(n["type"]):
		"event":
			var payload: Dictionary = ctx["payload"]
			result = payload.get(out)
		"literal":
			result = n.get("value")
		"get_var":
			result = _vars.get(str(n.get("var", "")))
		"math":
			result = _math(id, n, ctx)
		"call":
			var results: Dictionary = ctx["results"]
			if results.has(id):
				result = results[id]
			else:
				result = _call(id, n, ctx)
		"for_loop":
			var loops: Dictionary = ctx["loops"]
			result = loops.get(id, 0)
		"get_state":
			result = get_state(str(n.get("machine", "")))
	_pure_depth -= 1
	return result


func _math(id: String, n: Dictionary, ctx: Dictionary) -> Variant:
	if _halted:
		return null
	var op: String = str(n.get("op", ""))
	var a: Variant = _pull(id, "a", ctx, 0)
	if op == "not":
		return not _truthy(a)
	var b: Variant = _pull(id, "b", ctx, 0)
	if _halted:
		return null
	match op:
		"and":
			return _truthy(a) and _truthy(b)
		"or":
			return _truthy(a) or _truthy(b)
		"compare":
			return _compare(str(n.get("cmp", "==")), a, b)
	if op == "add" and (typeof(a) == TYPE_STRING or typeof(b) == TYPE_STRING):
		return str(a) + str(b)
	if not (_is_num(a) and _is_num(b)):
		_err("math %s: '%s' needs numbers" % [id, op])
		return 0
	var both_int: bool = typeof(a) == TYPE_INT and typeof(b) == TYPE_INT
	var fa: float = float(a)
	var fb: float = float(b)
	match op:
		"add":
			return int(a) + int(b) if both_int else fa + fb
		"sub":
			return int(a) - int(b) if both_int else fa - fb
		"mul":
			return int(a) * int(b) if both_int else fa * fb
		"div":
			if fb == 0.0:
				_err("math %s: division by zero" % id)
				return 0.0
			return fa / fb
		"min":
			return mini(int(a), int(b)) if both_int else minf(fa, fb)
		"max":
			return maxi(int(a), int(b)) if both_int else maxf(fa, fb)
		"clamp":
			var c: Variant = _pull(id, "c", ctx, 1)
			if not _is_num(c):
				_err("math %s: clamp needs numbers" % id)
				return 0
			var lo: float = minf(fb, float(c))
			var hi: float = maxf(fb, float(c))
			var r: float = clampf(fa, lo, hi)
			if both_int and typeof(c) == TYPE_INT:
				return int(r)
			return r
	return 0


func _compare(cmp: String, a: Variant, b: Variant) -> bool:
	var comparable: bool = (_is_num(a) and _is_num(b)) or (typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING)
	var same: bool = (comparable or typeof(a) == typeof(b)) and a == b
	if cmp == "==":
		return same
	if cmp == "!=":
		return not same
	if not comparable:
		_err("compare '%s': operands are not comparable" % cmp)
		return false
	match cmp:
		"<":
			return a < b
		"<=":
			return a <= b
		">":
			return a > b
		">=":
			return a >= b
	return false


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING:
			return not (v as String).is_empty()
	return true


func _dict_of(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}


func _arr_of(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY:
		return v
	return []
