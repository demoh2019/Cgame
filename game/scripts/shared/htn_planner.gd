extends RefCounted
## Hierarchical Task Network planner, in the style of the HTN planners used
## by Horizon Zero Dawn (Guerrilla) and Transformers: Fall of Cybertron.
##
## Domain layout (plain data):
##   compound task  -> Array of methods, tried in order:
##                     {"preconditions": {key: value}, "subtasks": ["a", "b"]}
##   primitive task -> {"preconditions": {key: value}, "effects": {key: value}}
## A task is primitive when its entry is a Dictionary with an "effects" key.
## Planning decomposes depth first, simulating effects on a copy of the world
## state and backtracking to the next method when a branch dead-ends. Fully
## deterministic: methods are tried in declaration order.


## Returns the primitive task names to execute, or an empty array when the
## root task cannot be decomposed within `max_steps` expansions.
static func plan(domain: Dictionary, root_task: String, state: Dictionary, max_steps: int = 256) -> Array[String]:
	var budget: Array[int] = [max_steps]
	var found: Variant = _solve(domain, [root_task], state, budget)
	var out: Array[String] = []
	if found == null:
		return out
	for name in found:
		out.append(String(name))
	return out


static func _holds(state: Dictionary, conditions: Dictionary) -> bool:
	for key in conditions:
		if not state.has(key) or state[key] != conditions[key]:
			return false
	return true


## Returns an Array of primitive names, or null when this branch fails.
static func _solve(domain: Dictionary, tasks: Array, state: Dictionary, budget: Array[int]) -> Variant:
	if tasks.is_empty():
		return []
	budget[0] -= 1
	if budget[0] < 0:
		return null
	var head: String = String(tasks[0])
	var rest: Array = tasks.slice(1)
	if not domain.has(head):
		return null
	var entry: Variant = domain[head]
	if entry is Dictionary:
		var prim: Dictionary = entry
		if not _holds(state, prim.get("preconditions", {})):
			return null
		var next_state: Dictionary = state.duplicate()
		var effects: Dictionary = prim.get("effects", {})
		for key in effects:
			next_state[key] = effects[key]
		var tail: Variant = _solve(domain, rest, next_state, budget)
		if tail == null:
			return null
		var seq: Array = [head]
		seq.append_array(tail)
		return seq
	if entry is Array:
		var methods: Array = entry
		for method in methods:
			var m: Dictionary = method
			if not _holds(state, m.get("preconditions", {})):
				continue
			var queue: Array = []
			queue.append_array(m.get("subtasks", []))
			queue.append_array(rest)
			var result: Variant = _solve(domain, queue, state, budget)
			if result != null:
				return result
			if budget[0] < 0:
				return null
	return null
