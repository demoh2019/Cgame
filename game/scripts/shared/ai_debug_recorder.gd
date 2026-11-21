@tool
extends RefCounted
## AI planning debugger backend: per-agent ring buffers of decision records
## {time, kind: htn|goap|state_tree|utility, data}. Feed it from HTN / GOAP planners,
## StateTree.debug_path() and Utility AI scoring; query timelines, diff plans and get
## human-readable explanations. Original implementation (no third-party code); the
## idea mirrors the Unreal Gameplay Debugger / Visual Logger AI views.

const KINDS: Array[String] = ["htn", "goap", "state_tree", "utility"]

var capacity: int = 256
## Optional Callable() -> float supplying the timestamp; otherwise set_time()/advance() drive it.
var time_source: Callable = Callable()

var _clock: float = 0.0
var _buffers: Dictionary = {}
var _dropped: Dictionary = {}


func _init(p_capacity: int = 256) -> void:
	capacity = maxi(p_capacity, 1)


func set_time(t: float) -> void:
	_clock = t


func advance(dt: float) -> void:
	_clock += dt


func now() -> float:
	if time_source.is_valid():
		return float(time_source.call())
	return _clock


static func agent_key(agent: Variant) -> String:
	if agent is Node:
		var n: Node = agent
		return String(n.name)
	return str(agent)


func record_htn(agent: Variant, plan: Array, state: Dictionary, at: float = -1.0) -> Dictionary:
	return _push(agent, "htn", {"plan": _names(plan), "state": state.duplicate(true)}, at)


func record_goap(agent: Variant, plan: Array, cost: float, at: float = -1.0) -> Dictionary:
	return _push(agent, "goap", {"plan": _names(plan), "cost": cost}, at)


## `path` is an Array of state ids or the "A/B/C" string from StateTree.debug_path().
func record_state_tree(agent: Variant, path: Variant, at: float = -1.0) -> Dictionary:
	var parts: Array[String] = []
	if path is String or path is StringName:
		var s: String = String(path)
		if s != "" and s != "(inactive)":
			for p in s.split("/"):
				parts.append(p)
	elif path is Array:
		parts = _names(path)
	return _push(agent, "state_tree", {"path": parts}, at)


func record_utility(agent: Variant, scores: Dictionary, chosen: Variant, at: float = -1.0) -> Dictionary:
	var copy: Dictionary = {}
	for k in scores:
		copy[str(k)] = float(scores[k])
	return _push(agent, "utility", {"scores": copy, "chosen": str(chosen)}, at)


func agents() -> Array[String]:
	var out: Array[String] = []
	for k in _buffers:
		out.append(String(k))
	out.sort()
	return out


func count(agent: Variant) -> int:
	var buf: Array = _buffers.get(agent_key(agent), [])
	return buf.size()


## Records overwritten by the ring buffer for this agent.
func dropped(agent: Variant) -> int:
	return int(_dropped.get(agent_key(agent), 0))


func clear(agent: Variant = null) -> void:
	if agent == null:
		_buffers.clear()
		_dropped.clear()
		return
	var key := agent_key(agent)
	_buffers.erase(key)
	_dropped.erase(key)


## Records with t0 <= time <= t1, oldest first; `kind` "" = all kinds.
func timeline(agent: Variant, t0: float, t1: float, kind: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var buf: Array = _buffers.get(agent_key(agent), [])
	for r_v in buf:
		var r: Dictionary = r_v
		var rt: float = float(r["time"])
		if rt < t0 or rt > t1:
			continue
		if kind != "" and String(r["kind"]) != kind:
			continue
		out.append(r)
	return out


## Latest record of `kind` at or before `time` (empty Dictionary when none).
func latest(agent: Variant, kind: String, time: float) -> Dictionary:
	var buf: Array = _buffers.get(agent_key(agent), [])
	var i: int = buf.size() - 1
	while i >= 0:
		var r: Dictionary = buf[i]
		if String(r["kind"]) == kind and float(r["time"]) <= time:
			return r
		i -= 1
	return {}


## The record of `kind` immediately before `rec` in time order (empty when none).
func previous(agent: Variant, kind: String, rec: Dictionary) -> Dictionary:
	var buf: Array = _buffers.get(agent_key(agent), [])
	var idx: int = -1
	for i in buf.size():
		var r: Dictionary = buf[i]
		if int(r["seq"]) == int(rec.get("seq", -1)):
			idx = i
			break
	var j: int = idx - 1
	while j >= 0:
		var p: Dictionary = buf[j]
		if String(p["kind"]) == kind:
			return p
		j -= 1
	return {}


## {same, common_prefix, removed, added, reordered}: removed = steps of `a` after the common
## prefix, added = steps of `b` after it, reordered = same steps in a different order.
static func diff_plans(a: Array, b: Array) -> Dictionary:
	var an: Array[String] = _names(a)
	var bn: Array[String] = _names(b)
	var prefix: int = 0
	while prefix < an.size() and prefix < bn.size() and an[prefix] == bn[prefix]:
		prefix += 1
	var removed: Array[String] = an.slice(prefix)
	var added: Array[String] = bn.slice(prefix)
	var sa: Array[String] = an.duplicate()
	var sb: Array[String] = bn.duplicate()
	sa.sort()
	sb.sort()
	return {
		"same": an == bn,
		"common_prefix": prefix,
		"removed": removed,
		"added": added,
		"reordered": an != bn and sa == sb,
	}


## Plan changes for one planner kind over time: [{time, diff}] (first record diffs against []).
func plan_changes(agent: Variant, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var last: Array = []
	for r in timeline(agent, -INF, INF, kind):
		var d: Dictionary = r["data"]
		var plan: Array = d.get("plan", [])
		var df := diff_plans(last, plan)
		if not bool(df["same"]) or out.is_empty():
			out.append({"time": r["time"], "diff": df})
		last = plan
	return out


func export_json(indent: String = "") -> String:
	var agents_out: Dictionary = {}
	for k in _buffers:
		agents_out[k] = _buffers[k]
	return JSON.stringify({"capacity": capacity, "agents": agents_out}, indent)


## Human-readable reasoning for `agent` at `time`.
func explain(agent: Variant, time: float) -> String:
	var key := agent_key(agent)
	var lines: PackedStringArray = []
	for kind in KINDS:
		var rec: Dictionary = latest(agent, kind, time)
		if rec.is_empty():
			continue
		var d: Dictionary = rec["data"]
		var t: float = float(rec["time"])
		match kind:
			"htn", "goap":
				lines.append(_explain_plan(agent, kind, rec, d, t))
			"state_tree":
				var path: Array = d.get("path", [])
				lines.append("StateTree @%.2fs: active path %s." % [t, "/".join(PackedStringArray(path)) if not path.is_empty() else "(inactive)"])
			"utility":
				lines.append(_explain_utility(d, t))
	if lines.is_empty():
		return "No decisions recorded for %s by t=%.2fs." % [key, time]
	return "%s at t=%.2fs:\n%s" % [key, time, "\n".join(lines)]


# --- internals -------------------------------------------------------------

var _seq: int = 0


func _push(agent: Variant, kind: String, data: Dictionary, at: float) -> Dictionary:
	var key := agent_key(agent)
	if not _buffers.has(key):
		_buffers[key] = []
	var buf: Array = _buffers[key]
	_seq += 1
	var rec: Dictionary = {"seq": _seq, "time": at if at >= 0.0 else now(), "kind": kind, "data": data}
	buf.append(rec)
	while buf.size() > capacity:
		buf.pop_front()
		_dropped[key] = int(_dropped.get(key, 0)) + 1
	return rec


static func _names(items: Array) -> Array[String]:
	var out: Array[String] = []
	for v in items:
		out.append(str(v))
	return out


func _explain_plan(agent: Variant, kind: String, rec: Dictionary, d: Dictionary, t: float) -> String:
	var plan: Array = d.get("plan", [])
	var label: String = kind.to_upper()
	var s: String
	if plan.is_empty():
		s = "%s @%.2fs: no plan (goal already satisfied or unreachable)." % [label, t]
	else:
		s = "%s @%.2fs: %d-step plan %s" % [label, t, plan.size(), " -> ".join(PackedStringArray(plan))]
		if kind == "goap":
			s += " (total cost %.2f)" % float(d.get("cost", 0.0))
		s += "."
	var prev: Dictionary = previous(agent, kind, rec)
	if not prev.is_empty():
		var pd: Dictionary = prev["data"]
		var diff: Dictionary = diff_plans(pd.get("plan", []), plan)
		if bool(diff["same"]):
			s += " Plan unchanged."
		else:
			var removed: Array = diff["removed"]
			var added: Array = diff["added"]
			s += " Replanned after %d unchanged step(s): dropped [%s], added [%s]." % [
				int(diff["common_prefix"]), ", ".join(PackedStringArray(removed)), ", ".join(PackedStringArray(added))]
	return s


func _explain_utility(d: Dictionary, t: float) -> String:
	var scores: Dictionary = d.get("scores", {})
	var chosen: String = String(d.get("chosen", ""))
	var keys: Array = scores.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool:
		var sx: float = float(scores[x])
		var sy: float = float(scores[y])
		if sx != sy:
			return sx > sy
		return str(x) < str(y))
	if keys.is_empty():
		return "Utility @%.2fs: no options scored." % t
	var s := "Utility @%.2fs: chose '%s' (%.2f)" % [t, chosen, float(scores.get(chosen, 0.0))]
	var others: PackedStringArray = []
	for k in keys:
		if str(k) != chosen:
			others.append("'%s' %.2f" % [str(k), float(scores[k])])
	if not others.is_empty():
		s += " over " + ", ".join(others)
	var top: String = str(keys[0])
	if top != chosen:
		s += "; note '%s' scored higher but was not chosen (commitment or veto)" % top
	elif keys.size() > 1:
		s += "; margin %.2f" % (float(scores[keys[0]]) - float(scores[keys[1]]))
	return s + "."
