extends RefCounted
## Physics timeline profiler: per-step wall-clock timings by phase (broadphase, narrowphase,
## solve, integrate), contact / pair / sleeping counters, a bounded ring buffer, an aggregated
## report() and a Chrome trace (chrome://tracing, Perfetto) export: {"traceEvents": [...]}.
##
## Plug into DeterministicPhysics via `world.timeline = timeline` (duck typed hooks:
## begin_step / begin_phase / end_phase / end_step). Timings are wall clock and are never part
## of the simulation state, so profiling cannot affect determinism.
##
## Trace format reference: Chrome "Trace Event Format" (public spec; ph "X" complete events,
## "C" counters, "M" metadata). Original implementation, no third-party code.

const PHASES: Array[String] = ["broadphase", "narrowphase", "solve", "integrate"]

var capacity: int = 240

var _ring: Array[Dictionary] = []
var _cur: Dictionary = {}
var _phase_name: String = ""
var _phase_start: int = 0


func clear() -> void:
	_ring.clear()
	_cur = {}


func record_count() -> int:
	return _ring.size()


func records() -> Array[Dictionary]:
	return _ring


func begin_step(step_index: int) -> void:
	_cur = {"step": step_index, "start_us": Time.get_ticks_usec(), "dur_us": 0, "phases": []}


func begin_phase(phase: String) -> void:
	_phase_name = phase
	_phase_start = Time.get_ticks_usec()


func end_phase() -> void:
	if _cur.is_empty():
		return
	var now: int = Time.get_ticks_usec()
	(_cur["phases"] as Array).append({"name": _phase_name, "start_us": _phase_start, "dur_us": now - _phase_start})


func end_step(stats: Dictionary) -> void:
	if _cur.is_empty():
		return
	_cur["dur_us"] = Time.get_ticks_usec() - int(_cur["start_us"])
	for k in stats:
		_cur[k] = stats[k]
	_ring.append(_cur)
	while _ring.size() > maxi(capacity, 1):
		_ring.pop_front()
	_cur = {}


## Total microseconds spent in `phase` during one recorded step.
static func phase_us(rec: Dictionary, phase: String) -> int:
	var total: int = 0
	for ev in rec["phases"] as Array:
		var e: Dictionary = ev
		if e["name"] == phase:
			total += int(e["dur_us"])
	return total


func report() -> Dictionary:
	var n: int = _ring.size()
	var out: Dictionary = {"steps": n, "avg_step_us": 0.0, "max_step_us": 0, "phases": {},
		"avg_contacts": 0.0, "max_contacts": 0, "max_sleeping": 0, "last": {}}
	if n == 0:
		return out
	var sum_step: int = 0
	var max_step: int = 0
	var sum_contacts: int = 0
	var max_contacts: int = 0
	var max_sleeping: int = 0
	var phase_sum: Dictionary = {}
	var phase_max: Dictionary = {}
	for p in PHASES:
		phase_sum[p] = 0
		phase_max[p] = 0
	for rec in _ring:
		var d: int = int(rec["dur_us"])
		sum_step += d
		max_step = maxi(max_step, d)
		var c: int = int(rec.get("contacts", 0))
		sum_contacts += c
		max_contacts = maxi(max_contacts, c)
		max_sleeping = maxi(max_sleeping, int(rec.get("sleeping", 0)))
		for p in PHASES:
			var us: int = phase_us(rec, p)
			phase_sum[p] = int(phase_sum[p]) + us
			phase_max[p] = maxi(int(phase_max[p]), us)
	var phases: Dictionary = {}
	for p in PHASES:
		phases[p] = {"avg_us": float(phase_sum[p]) / float(n), "max_us": phase_max[p], "total_us": phase_sum[p]}
	out["avg_step_us"] = float(sum_step) / float(n)
	out["max_step_us"] = max_step
	out["phases"] = phases
	out["avg_contacts"] = float(sum_contacts) / float(n)
	out["max_contacts"] = max_contacts
	out["max_sleeping"] = max_sleeping
	var last: Dictionary = _ring[n - 1]
	out["last"] = {"step": last["step"], "dur_us": last["dur_us"], "contacts": last.get("contacts", 0),
		"pairs": last.get("pairs", 0), "sleeping": last.get("sleeping", 0), "bodies": last.get("bodies", 0)}
	return out


func report_text() -> String:
	var r: Dictionary = report()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("physics: %d steps, avg %.1f us, max %d us, contacts avg %.1f max %d, sleeping max %d" % [
		r["steps"], r["avg_step_us"], r["max_step_us"], r["avg_contacts"], r["max_contacts"], r["max_sleeping"]])
	var phases: Dictionary = r["phases"]
	for p in PHASES:
		if phases.has(p):
			var ph: Dictionary = phases[p]
			lines.append("  %-12s avg %8.1f us  max %d us" % [p, ph["avg_us"], ph["max_us"]])
	return "\n".join(lines)


## Chrome trace object. Timestamps are microseconds relative to the oldest recorded step.
func to_trace() -> Dictionary:
	var events: Array = []
	events.append({"name": "process_name", "ph": "M", "pid": 1, "tid": 1, "args": {"name": "physics"}})
	events.append({"name": "thread_name", "ph": "M", "pid": 1, "tid": 1, "args": {"name": "step"}})
	if _ring.is_empty():
		return {"traceEvents": events, "displayTimeUnit": "ms"}
	var origin: int = int(_ring[0]["start_us"])
	for rec in _ring:
		var start: int = int(rec["start_us"]) - origin
		events.append({"name": "step %d" % int(rec["step"]), "cat": "physics", "ph": "X", "ts": start,
			"dur": int(rec["dur_us"]), "pid": 1, "tid": 1,
			"args": {"contacts": rec.get("contacts", 0), "pairs": rec.get("pairs", 0),
				"sleeping": rec.get("sleeping", 0), "bodies": rec.get("bodies", 0)}})
		for ev in rec["phases"] as Array:
			var e: Dictionary = ev
			events.append({"name": e["name"], "cat": "physics.phase", "ph": "X",
				"ts": int(e["start_us"]) - origin, "dur": int(e["dur_us"]), "pid": 1, "tid": 1})
		events.append({"name": "contacts", "ph": "C", "ts": start, "pid": 1, "tid": 1,
			"args": {"contacts": rec.get("contacts", 0), "sleeping": rec.get("sleeping", 0)}})
	return {"traceEvents": events, "displayTimeUnit": "ms"}


func export_json() -> String:
	return JSON.stringify(to_trace())
