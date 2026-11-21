extends RefCounted
## Dependency-aware task graph scheduler on top of WorkerThreadPool.
##
## Design references (concepts only, no code copied; original GDScript):
##  - Taskflow, MIT, https://github.com/taskflow/taskflow (task graph, dependency edges, DOT dump)
##  - enkiTS, zlib, https://github.com/dougbinks/enkiTS (task sets with dependencies)
##  - Gyrling, "Parallelizing the Naughty Dog engine using fibers" (GDC 2015): job counters and
##    dependency waits. Fibers are not available in Godot, so ready tasks execute in waves.
##  - Unreal TaskGraph / Unity Jobs dependency handles (public documentation).
##
## A task callable returning `false` or a Dictionary with an "error" key is a failure; a thrown
## script error cannot be caught in GDScript, so tasks signal failure through the return value.
## Failed tasks cancel all transitive dependants. Tasks registered with thread_safe = false run on
## the calling thread while the pooled tasks of the same wave execute.

enum State { PENDING, DONE, FAILED, CANCELLED }

class _Task:
	var name: String = ""
	var callable: Callable
	var deps: PackedStringArray = PackedStringArray()
	var thread_safe: bool = true
	var index: int = 0
	var state: int = 0
	var result: Variant = null
	var error: String = ""
	var start_us: int = 0
	var duration_us: int = 0
	var thread_id: int = 0
	var wave: int = -1

var _tasks: Dictionary = {}
var _list: Array[_Task] = []
var _last_total_us: int = 0
var _wave_count: int = 0


## Registers a task. Returns the task name, or "" if the name is empty/duplicate or the
## dependencies would form a cycle (the task is not added in that case).
func add_task(task_name: String, callable: Callable, deps: PackedStringArray = PackedStringArray(), thread_safe: bool = true) -> String:
	if task_name == "" or _tasks.has(task_name):
		push_error("TaskGraph: invalid or duplicate task '%s'" % task_name)
		return ""
	for d in deps:
		if d == task_name or _reaches(d, task_name):
			push_error("TaskGraph: task '%s' would create a dependency cycle" % task_name)
			return ""
	var t := _Task.new()
	t.name = task_name
	t.callable = callable
	t.deps = deps
	t.thread_safe = thread_safe
	t.index = _list.size()
	_tasks[task_name] = t
	_list.append(t)
	return task_name


## Adds an extra dependency edge; rejected (false) if it would create a cycle or names unknown tasks.
func add_dependency(task_name: String, dep: String) -> bool:
	if not _tasks.has(task_name) or not _tasks.has(dep) or task_name == dep:
		return false
	if _reaches(dep, task_name):
		return false
	var t: _Task = _tasks[task_name]
	if not t.deps.has(dep):
		t.deps.append(dep)
	return true


func has_task(task_name: String) -> bool:
	return _tasks.has(task_name)


func task_count() -> int:
	return _list.size()


func clear() -> void:
	_tasks.clear()
	_list.clear()
	_last_total_us = 0
	_wave_count = 0


## True when `from` depends (transitively) on `target`.
func _reaches(from: String, target: String) -> bool:
	var stack: Array[String] = [from]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if cur == target:
			return true
		if seen.has(cur) or not _tasks.has(cur):
			continue
		seen[cur] = true
		var t: _Task = _tasks[cur]
		for d in t.deps:
			stack.append(d)
	return false


## Dependencies naming tasks that were never added.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for t in _list:
		for d in t.deps:
			if not _tasks.has(d):
				errors.append("%s depends on unknown task %s" % [t.name, d])
	return errors


## Deterministic topological order (Kahn; ties broken by insertion order).
func topological_order() -> PackedStringArray:
	var indeg: Dictionary = {}
	var dependants: Dictionary = {}
	for t in _list:
		var n := 0
		for d in t.deps:
			if _tasks.has(d):
				n += 1
				if not dependants.has(d):
					dependants[d] = []
				dependants[d].append(t.name)
		indeg[t.name] = n
	var ready: Array[int] = []
	for t in _list:
		if int(indeg[t.name]) == 0:
			ready.append(t.index)
	var out := PackedStringArray()
	while not ready.is_empty():
		ready.sort()
		var idx: int = ready.pop_front()
		var t: _Task = _list[idx]
		out.append(t.name)
		if dependants.has(t.name):
			var dl: Array = dependants[t.name]
			for dn in dl:
				var key: String = dn
				indeg[key] = int(indeg[key]) - 1
				if int(indeg[key]) == 0:
					var dt: _Task = _tasks[key]
					ready.append(dt.index)
	return out


func _exec(t: _Task) -> void:
	t.thread_id = OS.get_thread_caller_id()
	t.start_us = Time.get_ticks_usec()
	if not t.callable.is_valid():
		t.error = "invalid callable"
	else:
		var r: Variant = t.callable.call()
		t.result = r
		if r is bool and not r:
			t.error = "task returned false"
		elif r is Dictionary and r.has("error"):
			t.error = str(r["error"])
	t.duration_us = Time.get_ticks_usec() - t.start_us


## Executes the graph. Returns {ok, order, failed, cancelled, waves, total_ms, error}.
func run() -> Dictionary:
	var out := {"ok": false, "order": PackedStringArray(), "failed": PackedStringArray(),
		"cancelled": PackedStringArray(), "waves": 0, "total_ms": 0.0, "error": ""}
	var problems := validate()
	if not problems.is_empty():
		out["error"] = problems[0]
		return out
	var order := topological_order()
	if order.size() != _list.size():
		out["error"] = "cycle detected"
		return out
	for t in _list:
		t.state = State.PENDING
		t.result = null
		t.error = ""
		t.duration_us = 0
		t.start_us = 0
		t.wave = -1
	var t_begin := Time.get_ticks_usec()
	var wave_no := 0
	while true:
		var wave: Array[_Task] = []
		for tname in order:
			var t: _Task = _tasks[tname]
			if t.state != State.PENDING:
				continue
			var blocked := false
			var dead := false
			for d in t.deps:
				var ds: int = (_tasks[d] as _Task).state
				if ds == State.FAILED or ds == State.CANCELLED:
					dead = true
				elif ds == State.PENDING:
					blocked = true
			if dead:
				t.state = State.CANCELLED
			elif not blocked:
				wave.append(t)
		if wave.is_empty():
			break
		_run_wave(wave, wave_no)
		wave_no += 1
	_wave_count = wave_no
	_last_total_us = Time.get_ticks_usec() - t_begin
	var failed := PackedStringArray()
	var cancelled := PackedStringArray()
	for tname in order:
		var t: _Task = _tasks[tname]
		if t.state == State.FAILED:
			failed.append(tname)
		elif t.state == State.CANCELLED:
			cancelled.append(tname)
	out["ok"] = failed.is_empty() and cancelled.is_empty()
	out["order"] = order
	out["failed"] = failed
	out["cancelled"] = cancelled
	out["waves"] = wave_no
	out["total_ms"] = _last_total_us / 1000.0
	return out


func _run_wave(wave: Array[_Task], wave_no: int) -> void:
	var ids: Array[int] = []
	var local: Array[_Task] = []
	for t in wave:
		t.wave = wave_no
		if t.thread_safe and wave.size() > 1:
			ids.append(WorkerThreadPool.add_task(_exec.bind(t), false, t.name))
		else:
			local.append(t)
	for t in local:
		_exec(t)
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	for t in wave:
		t.state = State.FAILED if t.error != "" else State.DONE


func result_of(task_name: String) -> Variant:
	if not _tasks.has(task_name):
		return null
	return (_tasks[task_name] as _Task).result


func state_of(task_name: String) -> int:
	if not _tasks.has(task_name):
		return -1
	return (_tasks[task_name] as _Task).state


func error_of(task_name: String) -> String:
	if not _tasks.has(task_name):
		return ""
	return (_tasks[task_name] as _Task).error


## Per-task timing: {start_us, end_us, duration_ms, wave, thread_id, thread_safe}.
func timing(task_name: String) -> Dictionary:
	if not _tasks.has(task_name):
		return {}
	var t: _Task = _tasks[task_name]
	return {"start_us": t.start_us, "end_us": t.start_us + t.duration_us, "duration_ms": t.duration_us / 1000.0,
		"wave": t.wave, "thread_id": t.thread_id, "thread_safe": t.thread_safe}


## Results keyed by task name, inserted in deterministic topological order.
func results() -> Dictionary:
	var out: Dictionary = {}
	for tname in topological_order():
		out[tname] = (_tasks[tname] as _Task).result
	return out


## Longest dependency chain by measured duration (cost 1.0 ms when a task has not run).
func critical_path() -> Array:
	var order := topological_order()
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var best_end := ""
	var best := -1.0
	for tname in order:
		var t: _Task = _tasks[tname]
		var base := 0.0
		var from := ""
		for d in t.deps:
			if dist.has(d) and float(dist[d]) > base:
				base = float(dist[d])
				from = d
		dist[tname] = base + _cost_ms(t)
		prev[tname] = from
		if float(dist[tname]) > best:
			best = float(dist[tname])
			best_end = tname
	var path: Array = []
	var cur := best_end
	while cur != "":
		path.push_front(cur)
		cur = String(prev[cur])
	return path


func critical_path_ms() -> float:
	var total := 0.0
	for tname in critical_path():
		total += _cost_ms(_tasks[tname])
	return total


func _cost_ms(t: _Task) -> float:
	return t.duration_us / 1000.0 if t.duration_us > 0 else 1.0 if t.state == State.PENDING else 0.001


## Graphviz DOT; critical path nodes/edges are red, failed tasks filled, cancelled dashed.
func to_dot() -> String:
	var crit: Array = critical_path()
	var s := "digraph TaskGraph {\n\trankdir=LR;\n\tnode [shape=box];\n"
	for t in _list:
		var attrs := "label=\"%s\\n%.2f ms\"" % [t.name, t.duration_us / 1000.0]
		if not t.thread_safe:
			attrs += ", shape=octagon"
		if t.state == State.FAILED:
			attrs += ", style=filled, fillcolor=tomato"
		elif t.state == State.CANCELLED:
			attrs += ", style=dashed"
		elif crit.has(t.name):
			attrs += ", color=red"
		s += "\t\"%s\" [%s];\n" % [t.name, attrs]
	for t in _list:
		for d in t.deps:
			var on_crit := crit.has(d) and crit.has(t.name) and crit.find(t.name) == crit.find(d) + 1
			s += "\t\"%s\" -> \"%s\"%s;\n" % [d, t.name, " [color=red]" if on_crit else ""]
	return s + "}\n"
