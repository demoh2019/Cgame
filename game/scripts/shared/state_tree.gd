extends RefCounted
## Hierarchical StateTree runtime in the spirit of Unreal Engine 5's StateTree
## (states with enter conditions, tasks, evaluators, prioritised transitions,
## linked subtrees). Original GDScript implementation written from the public
## concept description; no third-party source code was copied. Callables are
## registered by name so assets stay plain data (a whitelist).
##
## Asset dictionary:
##   {"name": String, "root": String,
##    "evaluators": [String | {"fn": String, "args": Dictionary}],
##    "states": {id: {"children": [id], "conditions": [cond], "tasks": [task],
##                    "link": subtree_name,
##                    "transitions": [{"trigger": "on_completed"|"on_failed"|"on_tick"|"on_event",
##                                     "event": String, "condition": cond,
##                                     "target": id | "$succeeded" | "$failed",
##                                     "priority": int}]}}}
## cond: String (registered condition), {"fn","args","not"}, {"key","op","value"}
##       (built-in context compare) or an Array of conds that must all pass.
## task: String or {"fn","args"}. A state without tasks never completes by itself.
## Selection: from the root, the first child (depth-first) whose enter conditions
## pass; a state with children but no selectable child is not selectable.

enum Status { RUNNING, SUCCEEDED, FAILED }

const TRIGGERS: PackedStringArray = ["on_completed", "on_failed", "on_tick", "on_event"]
const MAX_LINK_DEPTH := 8
const END_SUCCEEDED := "$succeeded"
const END_FAILED := "$failed"

var errors: Array[String] = []
var tree_status: int = Status.SUCCEEDED
var running: bool = false
var active_path: Array[String] = []
## Optional trace of enter/exit calls ("enter:id" / "exit:id") for debugging and tests.
var trace: Array[String] = []

var _tasks: Dictionary = {}
var _conditions: Dictionary = {}
var _evaluators: Dictionary = {}
var _subtrees: Dictionary = {}
var _asset: Dictionary = {}
var _states: Dictionary = {}
var _root: String = ""
var _events: Array = []
var _task_status: Dictionary = {}


## Registers a task. Callables are optional: enter(ctx, params), tick(ctx, dt, params) -> Status, exit(ctx, params).
func register_task(task_name: String, enter: Callable = Callable(), tick: Callable = Callable(), exit: Callable = Callable()) -> void:
	_tasks[task_name] = {"enter": enter, "tick": tick, "exit": exit}


## cond Callable: (ctx: Dictionary, args: Dictionary) -> bool
func register_condition(cond_name: String, fn: Callable) -> void:
	_conditions[cond_name] = fn


## Evaluator Callable: (ctx: Dictionary, dt: float, args: Dictionary) -> Dictionary (merged into ctx) or null.
func register_evaluator(eval_name: String, fn: Callable) -> void:
	_evaluators[eval_name] = fn


func register_subtree(subtree_name: String, asset: Dictionary) -> void:
	_subtrees[subtree_name] = asset


## Validates an asset against registered names. Returns a list of error strings (empty = ok).
func validate(asset: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var out: Dictionary = {}
	var root := _flatten(asset, "", out, 0, errs)
	if root != "" and errs.is_empty():
		var visiting: Dictionary = {}
		_check_cycles(root, out, visiting, errs)
	return errs


## Validates, flattens linked subtrees and installs the asset. False on error (see `errors`).
func set_asset(asset: Dictionary) -> bool:
	errors = validate(asset)
	if not errors.is_empty():
		return false
	_asset = asset
	_states = {}
	var ignore: Array[String] = []
	_root = _flatten(asset, "", _states, 0, ignore)
	_reset_runtime()
	return true


func start(context: Dictionary) -> bool:
	if _root == "":
		return false
	_reset_runtime()
	var path := _select(_root, context)
	if path.is_empty():
		tree_status = Status.FAILED
		return false
	running = true
	tree_status = Status.RUNNING
	_apply_path(path, 0, context)
	return true


func stop(context: Dictionary) -> void:
	if running:
		_exit_from(0, context)
	running = false


func send_event(event_name: String, payload: Variant = null) -> void:
	_events.append({"name": event_name, "payload": payload})


func tick(dt: float, context: Dictionary) -> int:
	if not running:
		return tree_status
	_run_evaluators(dt, context)
	var events := _events
	_events = []
	for ev_v in events:
		var ev: Dictionary = ev_v
		if _try_transition("on_event", ev, context):
			if not running:
				return tree_status
	_tick_tasks(dt, context)
	var trigger := ""
	var origin := -1
	for i in range(active_path.size() - 1, -1, -1):
		var st: int = _state_status(active_path[i])
		if st != Status.RUNNING:
			trigger = "on_completed" if st == Status.SUCCEEDED else "on_failed"
			origin = i
			break
	if trigger != "":
		if _try_transition(trigger, {}, context, origin):
			return tree_status
	if _try_transition("on_tick", {}, context):
		return tree_status
	if trigger != "":
		# Completed or failed with nothing to transition to: the tree itself finishes.
		_finish(Status.SUCCEEDED if trigger == "on_completed" else Status.FAILED, context)
	return tree_status


func debug_path() -> String:
	var parts: PackedStringArray = []
	for id in active_path:
		parts.append(id)
	return "/".join(parts) if not parts.is_empty() else "(inactive)"


func current_state() -> String:
	return active_path.back() if not active_path.is_empty() else ""


func is_active(state_id: String) -> bool:
	return active_path.has(state_id)


# --- internals -------------------------------------------------------------

func _reset_runtime() -> void:
	active_path = []
	running = false
	tree_status = Status.SUCCEEDED
	_events = []
	_task_status = {}


func _flatten(asset: Dictionary, prefix: String, out: Dictionary, depth: int, errs: Array[String]) -> String:
	if depth > MAX_LINK_DEPTH:
		errs.append("%slinked subtree depth exceeds %d (recursive link?)" % [prefix, MAX_LINK_DEPTH])
		return ""
	if not asset.has("states") or not (asset["states"] is Dictionary):
		errs.append("%sasset has no 'states' dictionary" % prefix)
		return ""
	var states: Dictionary = asset["states"]
	var root_id: String = str(asset.get("root", ""))
	if root_id == "" or not states.has(root_id):
		errs.append("%sroot '%s' is not a defined state" % [prefix, root_id])
		return ""
	var evs: Array = asset.get("evaluators", [])
	for ev_v in evs:
		var ev: Dictionary = _norm(ev_v)
		if not _evaluators.has(ev["fn"]):
			errs.append("%sunknown evaluator '%s'" % [prefix, ev["fn"]])
	for key in states:
		var id: String = str(key)
		var s: Dictionary = states[key]
		var node: Dictionary = {"id": prefix + id, "local": id, "children": [], "tasks": [],
				"conditions": s.get("conditions", []), "transitions": [], "parent": ""}
		var kids: Array = s.get("children", [])
		for c in kids:
			var cid: String = str(c)
			if not states.has(cid):
				errs.append("%sstate '%s' lists unknown child '%s'" % [prefix, id, cid])
			else:
				node["children"].append(prefix + cid)
		var tasks: Array = s.get("tasks", [])
		for task_v in tasks:
			var task: Dictionary = _norm(task_v)
			if not _tasks.has(task["fn"]):
				errs.append("%sstate '%s' uses unregistered task '%s'" % [prefix, id, task["fn"]])
			node["tasks"].append(task)
		_check_cond(s.get("conditions", []), prefix + id + " enter", errs)
		var trs: Array = s.get("transitions", [])
		for tr_v in trs:
			var tr: Dictionary = tr_v
			var trigger: String = str(tr.get("trigger", "on_completed"))
			if not TRIGGERS.has(trigger):
				errs.append("%sstate '%s' has transition with invalid trigger '%s'" % [prefix, id, trigger])
			if trigger == "on_event" and str(tr.get("event", "")) == "":
				errs.append("%sstate '%s' on_event transition has no event name" % [prefix, id])
			var target: String = str(tr.get("target", ""))
			if target != END_SUCCEEDED and target != END_FAILED and not states.has(target):
				errs.append("%sstate '%s' transition targets unknown state '%s'" % [prefix, id, target])
			_check_cond(tr.get("condition", []), prefix + id + " transition", errs)
			var real_target: String = target if target.begins_with("$") else prefix + target
			node["transitions"].append({"trigger": trigger, "event": str(tr.get("event", "")),
					"condition": tr.get("condition", []), "target": real_target,
					"priority": int(tr.get("priority", 0))})
		if s.has("link"):
			var link: String = str(s["link"])
			if not _subtrees.has(link):
				errs.append("%sstate '%s' links unknown subtree '%s'" % [prefix, id, link])
			else:
				var sub_root := _flatten(_subtrees[link], "%s%s/" % [prefix, id], out, depth + 1, errs)
				if sub_root != "":
					node["children"].append(sub_root)
		out[prefix + id] = node
	for key in out:
		var nd: Dictionary = out[key]
		for c in nd["children"]:
			if out.has(c):
				var child: Dictionary = out[c]
				child["parent"] = nd["id"]
	return prefix + root_id


func _check_cond(cond: Variant, where: String, errs: Array[String]) -> void:
	if cond is Array:
		for c in cond:
			_check_cond(c, where, errs)
	elif cond is String or cond is StringName:
		if str(cond) != "" and not _conditions.has(str(cond)):
			errs.append("%s: unregistered condition '%s'" % [where, str(cond)])
	elif cond is Dictionary:
		var d: Dictionary = cond
		if d.has("fn"):
			if not _conditions.has(str(d["fn"])):
				errs.append("%s: unregistered condition '%s'" % [where, str(d["fn"])])
		elif not d.has("key"):
			errs.append("%s: condition needs 'fn' or 'key'" % where)
	elif cond != null:
		errs.append("%s: malformed condition" % where)


func _check_cycles(id: String, out: Dictionary, visiting: Dictionary, errs: Array[String]) -> void:
	if visiting.has(id):
		errs.append("cycle in state hierarchy at '%s'" % id)
		return
	visiting[id] = true
	var nd: Dictionary = out[id]
	for c in nd["children"]:
		if errs.is_empty():
			_check_cycles(str(c), out, visiting, errs)
	visiting.erase(id)


func _norm(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		if not d.has("args"):
			d = d.duplicate()
			d["args"] = {}
		return d
	return {"fn": str(v), "args": {}}


func _eval_cond(cond: Variant, ctx: Dictionary) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c in cond:
			if not _eval_cond(c, ctx):
				return false
		return true
	var result := true
	if cond is Dictionary:
		var d: Dictionary = cond
		if d.has("fn"):
			var fn: Callable = _conditions[str(d["fn"])]
			var args: Dictionary = d.get("args", {})
			result = bool(fn.call(ctx, args))
		else:
			result = _compare(ctx.get(str(d["key"]), null), str(d.get("op", "==")), d.get("value", null))
		if bool(d.get("not", false)):
			result = not result
		return result
	var name := str(cond)
	if name == "":
		return true
	var f: Callable = _conditions[name]
	return bool(f.call(ctx, {}))


func _compare(a: Variant, op: String, b: Variant) -> bool:
	if a == null:
		return false
	match op:
		"==": return a == b
		"!=": return a != b
		"<": return a < b
		"<=": return a <= b
		">": return a > b
		">=": return a >= b
	return false


## Depth-first selection. Returns the path root..leaf, or [] when not selectable.
func _select(id: String, ctx: Dictionary) -> Array[String]:
	var nd: Dictionary = _states[id]
	if not _eval_cond(nd["conditions"], ctx):
		return []
	var kids: Array = nd["children"]
	if kids.is_empty():
		return [id]
	for c in kids:
		var sub := _select(str(c), ctx)
		if not sub.is_empty():
			var path: Array[String] = [id]
			path.append_array(sub)
			return path
	return []


func _run_evaluators(dt: float, ctx: Dictionary) -> void:
	var evs: Array = _asset.get("evaluators", [])
	for ev_v in evs:
		var ev: Dictionary = _norm(ev_v)
		var fn: Callable = _evaluators[str(ev["fn"])]
		var res: Variant = fn.call(ctx, dt, ev["args"])
		if res is Dictionary:
			ctx.merge(res, true)


func _tick_tasks(dt: float, ctx: Dictionary) -> void:
	for id in active_path:
		var nd: Dictionary = _states[id]
		var tasks: Array = nd["tasks"]
		var statuses: Array = _task_status[id]
		for i in tasks.size():
			if int(statuses[i]) != Status.RUNNING:
				continue
			var task: Dictionary = tasks[i]
			var reg: Dictionary = _tasks[str(task["fn"])]
			var tick_fn: Callable = reg["tick"]
			if tick_fn.is_valid():
				var params := _params(task, id)
				statuses[i] = int(tick_fn.call(ctx, dt, params))


func _state_status(id: String) -> int:
	var statuses: Array = _task_status.get(id, [])
	if statuses.is_empty():
		return Status.RUNNING
	var all_ok := true
	for s in statuses:
		if int(s) == Status.FAILED:
			return Status.FAILED
		if int(s) != Status.SUCCEEDED:
			all_ok = false
	return Status.SUCCEEDED if all_ok else Status.RUNNING


func _params(task: Dictionary, id: String) -> Dictionary:
	var p: Dictionary = (task["args"] as Dictionary).duplicate()
	p["_state"] = id
	return p


## Picks the best matching transition (highest priority, then deepest, then declaration order).
func _try_transition(trigger: String, ev: Dictionary, ctx: Dictionary, origin: int = -1) -> bool:
	var from_idx: int = origin if origin >= 0 else active_path.size() - 1
	var best: Dictionary = {}
	var best_priority := -2147483648
	var best_path: Array[String] = []
	var had_event := trigger == "on_event"
	if had_event:
		ctx["_event"] = ev["name"]
		ctx["_event_payload"] = ev["payload"]
	for i in range(from_idx, -1, -1):
		var nd: Dictionary = _states[active_path[i]]
		var trs: Array = nd["transitions"]
		for tr_v in trs:
			var tr: Dictionary = tr_v
			if tr["trigger"] != trigger:
				continue
			if had_event and tr["event"] != ev["name"]:
				continue
			var pr: int = tr["priority"]
			if not best.is_empty() and pr <= best_priority:
				continue
			if not _eval_cond(tr["condition"], ctx):
				continue
			var target: String = tr["target"]
			var path: Array[String] = []
			if not target.begins_with("$"):
				path = _select(target, ctx)
				if path.is_empty():
					continue
				path = _full_path(path, target)
			best = tr
			best_priority = pr
			best_path = path
	if had_event:
		ctx.erase("_event")
		ctx.erase("_event_payload")
	if best.is_empty():
		return false
	var tgt: String = best["target"]
	if tgt == END_SUCCEEDED:
		_finish(Status.SUCCEEDED, ctx)
	elif tgt == END_FAILED:
		_finish(Status.FAILED, ctx)
	else:
		var keep := 0
		while keep < active_path.size() and keep < best_path.size() and active_path[keep] == best_path[keep]:
			keep += 1
		# Targeting a state that is already active re-enters it.
		var target_depth := best_path.find(tgt)
		if keep > target_depth:
			keep = target_depth
		_exit_from(keep, ctx)
		_apply_path(best_path, keep, ctx)
	return true


## `_select` returns the path from the target down; prepend the target's ancestors.
func _full_path(sub: Array[String], target: String) -> Array[String]:
	var chain: Array[String] = []
	var cur: String = _states[target]["parent"]
	while cur != "":
		chain.push_front(cur)
		cur = _states[cur]["parent"]
	chain.append_array(sub)
	return chain


func _apply_path(path: Array[String], keep: int, ctx: Dictionary) -> void:
	active_path = path.duplicate()
	for i in range(keep, path.size()):
		var id := path[i]
		var nd: Dictionary = _states[id]
		var tasks: Array = nd["tasks"]
		var statuses: Array = []
		for _t in tasks:
			statuses.append(Status.RUNNING)
		_task_status[id] = statuses
		trace.append("enter:" + id)
		for task_v in tasks:
			var task: Dictionary = task_v
			var reg: Dictionary = _tasks[str(task["fn"])]
			var fn: Callable = reg["enter"]
			if fn.is_valid():
				fn.call(ctx, _params(task, id))


## Exits states from the leaf down to (and including) index `keep`.
func _exit_from(keep: int, ctx: Dictionary) -> void:
	for i in range(active_path.size() - 1, keep - 1, -1):
		var id := active_path[i]
		var nd: Dictionary = _states[id]
		var tasks: Array = nd["tasks"]
		for j in range(tasks.size() - 1, -1, -1):
			var task: Dictionary = tasks[j]
			var reg: Dictionary = _tasks[str(task["fn"])]
			var fn: Callable = reg["exit"]
			if fn.is_valid():
				fn.call(ctx, _params(task, id))
		trace.append("exit:" + id)
		_task_status.erase(id)
	active_path.resize(keep)


func _finish(status: int, ctx: Dictionary) -> void:
	_exit_from(0, ctx)
	running = false
	tree_status = status
