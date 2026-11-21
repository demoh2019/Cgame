extends RefCounted
## Goal-Oriented Action Planning, as popularised by F.E.A.R. (Jeff Orkin) and
## reused in Tomb Raider, Deus Ex: Human Revolution and many Unity/Unreal AI
## plugins. A* searches over world states: each action has a cost,
## preconditions and effects (all key -> value Dictionaries). The heuristic is
## the number of unsatisfied goal keys (scaled by the cheapest action cost so
## it stays a lower bound for unit-ish costs). Ties resolve by insertion order,
## so results are deterministic.


## Returns the action names of the cheapest plan reaching `goal`, or an empty
## array when it is unreachable or `max_nodes` expansions are exhausted.
static func plan(actions: Array, state: Dictionary, goal: Dictionary, max_nodes: int = 2048) -> Array[String]:
	var out: Array[String] = []
	if _satisfied(state, goal):
		return out
	var min_cost: float = 1.0
	for a in actions:
		var ad: Dictionary = a
		min_cost = minf(min_cost, float(ad.get("cost", 1.0)))
	min_cost = maxf(min_cost, 0.0)

	# Node arrays are parallel, indexed by insertion order (node id).
	var states: Array[Dictionary] = [state.duplicate()]
	var gs: Array[float] = [0.0]
	var parents: Array[int] = [-1]
	var names: Array[String] = [""]
	var open: Array[int] = [0]
	var best_g: Dictionary = {_key(state): 0.0}
	var expanded: int = 0

	while not open.is_empty():
		var pick: int = 0
		var pick_f: float = INF
		for i in open.size():
			var id: int = open[i]
			var f: float = gs[id] + _h(states[id], goal) * min_cost
			if f < pick_f - 0.000001:
				pick_f = f
				pick = i
		var cur: int = open[pick]
		open.remove_at(pick)
		if _satisfied(states[cur], goal):
			var node: int = cur
			while parents[node] != -1:
				out.push_front(names[node])
				node = parents[node]
			return out
		expanded += 1
		if expanded > max_nodes:
			return []
		var cur_key: String = _key(states[cur])
		if gs[cur] > float(best_g.get(cur_key, INF)) + 0.000001:
			continue
		for a in actions:
			var act: Dictionary = a
			if not _satisfied(states[cur], act.get("preconditions", {})):
				continue
			var next: Dictionary = states[cur].duplicate()
			var effects: Dictionary = act.get("effects", {})
			for k in effects:
				next[k] = effects[k]
			var g: float = gs[cur] + float(act.get("cost", 1.0))
			var nk: String = _key(next)
			if best_g.has(nk) and float(best_g[nk]) <= g + 0.000001:
				continue
			best_g[nk] = g
			states.append(next)
			gs.append(g)
			parents.append(cur)
			names.append(String(act.get("name", "")))
			open.append(states.size() - 1)
	return []


static func _satisfied(state: Dictionary, conditions: Dictionary) -> bool:
	for key in conditions:
		if not state.has(key) or state[key] != conditions[key]:
			return false
	return true


static func _h(state: Dictionary, goal: Dictionary) -> float:
	var n: int = 0
	for key in goal:
		if not state.has(key) or state[key] != goal[key]:
			n += 1
	return float(n)


static func _key(state: Dictionary) -> String:
	var keys: Array = state.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [str(k), var_to_str(state[k])])
	return ";".join(parts)
