extends RefCounted
## Hierarchical pathfinding (HPA*) and automatic off-mesh link generation.
## Path validity rule used here: 4-connected, every cell walkable.

const HierarchicalPathfinder = preload("res://scripts/shared/hierarchical_pathfinder.gd")
const OffMeshLinks = preload("res://scripts/shared/off_mesh_links.gd")

var _walls: Dictionary = {}


func _is_open(x: int, y: int) -> bool:
	return not _walls.has(Vector2i(x, y))


func _valid(path: PackedVector2Array, start: Vector2i, goal: Vector2i) -> bool:
	if path.is_empty() or Vector2i(path[0]) != start or Vector2i(path[path.size() - 1]) != goal:
		return false
	for i in path.size():
		var c := Vector2i(path[i])
		if not _is_open(c.x, c.y):
			return false
		if i > 0:
			var p := Vector2i(path[i - 1])
			if absi(c.x - p.x) + absi(c.y - p.y) != 1:
				return false
	return true


## Reference BFS: shortest 4-connected length or -1.
func _bfs(w: int, h: int, start: Vector2i, goal: Vector2i) -> int:
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c == goal:
			return dist[c]
		for d in HierarchicalPathfinder.DIRS:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or not _is_open(n.x, n.y) or dist.has(n):
				continue
			dist[n] = int(dist[c]) + 1
			queue.append(n)
	return -1


func run(t) -> void:
	var w := 24
	var h := 24
	t.current = "path around walls"
	_walls.clear()
	for y in range(0, 20):
		_walls[Vector2i(11, y)] = true
	var pf := HierarchicalPathfinder.new()
	pf.build(w, h, 8, _is_open)
	var start := Vector2i(1, 1)
	var goal := Vector2i(22, 2)
	var path := pf.find_path(start, goal)
	t.check(_valid(path, start, goal), "path valid across clusters")
	var shortest := _bfs(w, h, start, goal)
	t.check(path.size() - 1 >= shortest, "never shorter than plain BFS")
	t.check(path.size() - 1 <= shortest * 2, "near optimal (within 2x of BFS)")
	var detour := false
	for p in path:
		if p.y >= 20.0:
			detour = true
	t.check(detour, "route detours through the gap below the wall")
	t.eq(pf.find_path(start, start).size(), 1, "start equals goal")
	t.check(pf.find_path(start, Vector2i(11, 3)).is_empty(), "goal inside wall is unreachable")
	var local := pf.find_path(Vector2i(1, 1), Vector2i(6, 5))
	t.check(_valid(local, Vector2i(1, 1), Vector2i(6, 5)), "same-cluster path valid")
	t.eq(local.size() - 1, 9, "same-cluster path is optimal")

	t.current = "unreachable goal"
	_walls.clear()
	for y in range(0, h):
		_walls[Vector2i(12, y)] = true
	var sealed := HierarchicalPathfinder.new()
	sealed.build(w, h, 8, _is_open)
	t.check(sealed.find_path(Vector2i(1, 1), Vector2i(22, 22)).is_empty(), "sealed wall blocks goal")
	t.eq(_bfs(w, h, Vector2i(1, 1), Vector2i(22, 22)), -1, "reference agrees it is unreachable")

	t.current = "invalidate cluster"
	_walls.clear()
	var dyn := HierarchicalPathfinder.new()
	dyn.build(w, h, 8, _is_open)
	var a := Vector2i(2, 12)
	var b := Vector2i(21, 12)
	t.check(_valid(dyn.find_path(a, b), a, b), "open field path valid")
	for y in range(0, h):
		if y != 3:
			_walls[Vector2i(12, y)] = true
	for y in [0, 8, 16]:
		dyn.invalidate_cluster(Vector2i(12, y))
	var around := dyn.find_path(a, b)
	t.check(_valid(around, a, b), "path valid after adding a wall")
	var through_gap := false
	for p in around:
		if Vector2i(p) == Vector2i(12, 3):
			through_gap = true
	t.check(through_gap, "route squeezes through the only gap")
	_walls[Vector2i(12, 3)] = true
	dyn.invalidate_cluster(Vector2i(12, 3))
	t.check(dyn.find_path(a, b).is_empty(), "closing the gap makes goal unreachable")
	_walls.erase(Vector2i(12, 3))
	dyn.invalidate_cluster(Vector2i(12, 3))
	t.check(_valid(dyn.find_path(a, b), a, b), "reopening the gap restores the path")

	t.current = "corridor cache"
	_walls.clear()
	var cached := HierarchicalPathfinder.new()
	cached.build(w, h, 8, _is_open)
	t.eq(cached.cache_hits, 0, "no hits before queries")
	var first := cached.find_path(Vector2i(1, 1), Vector2i(20, 20))
	t.eq(cached.cache_hits, 0, "first query is a miss")
	var second := cached.find_path(Vector2i(2, 3), Vector2i(21, 19))
	t.eq(cached.cache_hits, 1, "same cluster pair reuses the abstract route")
	t.check(_valid(first, Vector2i(1, 1), Vector2i(20, 20)), "first path valid")
	t.check(_valid(second, Vector2i(2, 3), Vector2i(21, 19)), "cached path valid")
	cached.invalidate_cluster(Vector2i(10, 10))
	cached.find_path(Vector2i(1, 1), Vector2i(20, 20))
	t.eq(cached.cache_hits, 1, "invalidate drops cached routes")

	t.current = "many NPC routes cannot grow the abstract cache without bound"
	_walls.clear()
	var limited := HierarchicalPathfinder.new()
	limited.build(48, 48, 8, _is_open)
	var earliest_start := Vector2i(1, 1)
	var earliest_goal := Vector2i(9, 1)
	var recent_start := Vector2i.ZERO
	var recent_goal := Vector2i.ZERO
	for i in HierarchicalPathfinder.MAX_CACHED_ROUTES + 9:
		# Deterministic unique directed pairs from a 6x6 cluster map.
		var start_cluster: int = i / 35
		var goal_cluster: int = i % 35
		if goal_cluster >= start_cluster:
			goal_cluster += 1
		var a: Vector2i = Vector2i((start_cluster % 6) * 8 + 1,
			(start_cluster / 6) * 8 + 1)
		var b: Vector2i = Vector2i((goal_cluster % 6) * 8 + 1,
			(goal_cluster / 6) * 8 + 1)
		var candidate: PackedVector2Array = limited.find_path(a, b)
		t.check(_valid(candidate, a, b),
			"cached navigation paths remain physically traversable")
		t.check(limited.cached_route_count() <= HierarchicalPathfinder.MAX_CACHED_ROUTES,
			"cache size stays below fixed residency budget")
		recent_start = a
		recent_goal = b
	t.eq(limited.cached_route_count(), HierarchicalPathfinder.MAX_CACHED_ROUTES,
		"full route cache evicts older entries instead of growing indefinitely")
	var hits: int = limited.cache_hits
	t.check(_valid(limited.find_path(recent_start, recent_goal), recent_start, recent_goal),
		"most recent cached corridor can still be refined")
	t.eq(limited.cache_hits, hits + 1, "retained corridor is a cache hit")
	t.check(_valid(limited.find_path(earliest_start, earliest_goal), earliest_start, earliest_goal),
		"evicted old corridor is rebuilt on demand")
	t.eq(limited.cache_hits, hits + 1, "expired corridor cannot masquerade as a hit")
	limited.invalidate_cluster(Vector2i(16, 16))
	t.eq(limited.cached_route_count(), 0,
		"dynamic geometry changes invalidate resident corridors and FIFO order")

	t.current = "off-mesh links"
	# Rows 0 and 4 are three cells apart so they never link vertically.
	var heights := {}
	var open := {}
	for x in range(0, 8):
		open[Vector2i(x, 0)] = true
		heights[Vector2i(x, 0)] = 0.0
	# Row 0 gap: cells 3 and 4 unwalkable -> gap between x=2 and x=5.
	open.erase(Vector2i(3, 0))
	open.erase(Vector2i(4, 0))
	# Row 4: ledge from x=0 (h 2.0) down to x=1 (h 0.0), then small climb x=1->x=2 (h 1.0).
	heights[Vector2i(0, 4)] = 2.0
	heights[Vector2i(1, 4)] = 0.0
	heights[Vector2i(2, 4)] = 1.0
	for x in range(0, 3):
		open[Vector2i(x, 4)] = true
	var hf := func(x: int, y: int) -> float: return heights.get(Vector2i(x, y), 0.0)
	var wf := func(x: int, y: int) -> bool: return open.has(Vector2i(x, y))
	var links := OffMeshLinks.generate(8, 5, hf, wf)
	print(links)
	var by_kind := {"drop": [], "jump": [], "gap": []}
	for l in links:
		var d: Dictionary = l
		var kind: String = d["kind"]
		by_kind[kind].append(d)
	var drops: Array = by_kind["drop"]
	var jumps: Array = by_kind["jump"]
	var gaps: Array = by_kind["gap"]
	t.eq(drops.size(), 1, "one ledge drop")
	t.eq(jumps.size(), 1, "one small climb")
	t.eq(gaps.size(), 1, "one gap hop")
	if drops.size() == 1:
		var dl: Dictionary = drops[0]
		t.eq(dl["from"], Vector2i(0, 4), "drop starts at the high side")
		t.eq(dl["to"], Vector2i(1, 4), "drop lands on the low side")
		t.check(not bool(dl["bidirectional"]), "drops are one-way")
	if jumps.size() == 1:
		var jl: Dictionary = jumps[0]
		t.eq(jl["from"], Vector2i(1, 4), "climb starts low")
		t.eq(jl["to"], Vector2i(2, 4), "climb ends high")
		t.check(bool(jl["bidirectional"]), "climbs are two-way")
	if gaps.size() == 1:
		var gl: Dictionary = gaps[0]
		t.eq(gl["from"], Vector2i(2, 0), "gap starts before the hole")
		t.eq(gl["to"], Vector2i(5, 0), "gap ends after the hole")
		t.check(bool(gl["bidirectional"]), "gaps are two-way")
	var wide := OffMeshLinks.generate(8, 5, hf, wf, 3.0, 1.2, 1)
	var wide_gaps := 0
	for l in wide:
		var d2: Dictionary = l
		if d2["kind"] == "gap":
			wide_gaps += 1
	t.eq(wide_gaps, 0, "max_gap 1 rejects a two-cell gap")
	t.eq(OffMeshLinks.generate(8, 5, hf, wf).size(), links.size(), "generation is deterministic")
