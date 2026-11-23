extends RefCounted
## HPA*-style hierarchical pathfinding over a walkability grid for large streamed regions.
## Inspired by Botea et al., "Near Optimal Hierarchical Path-Finding" (HPA*): the grid is cut
## into square clusters, entrance nodes are placed on shared cluster borders, and an abstract
## graph is searched with A* before the route is refined to grid cells.
##
## Grid movement is 4-connected (every step is one cell up, down, left or right, cost 1).
## Paths are valid but not guaranteed to be the globally shortest (classic HPA* trade-off).
## Dynamic obstacles: change what `walkable` returns, then call invalidate_cluster() for each
## affected cell; only that cluster and its borders are rebuilt.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Border runs longer than this get extra entrance nodes at both ends (HPA* entrance rule).
const LONG_RUN := 6
const FAR := 1 << 30
const MAX_CACHED_ROUTES := 128 # Bounded resident abstract corridors per pathfinder.

## Abstract-route reuses (same start/goal cluster pair).
var cache_hits: int = 0

var width: int = 0
var height: int = 0
var cluster_size: int = 8

var _walkable: Callable
var _grid := PackedByteArray()
var _cw: int = 0
var _ch: int = 0
var _n_cell: Array[Vector2i] = []
var _n_cluster := PackedInt32Array()
var _n_alive := PackedByteArray()
var _adj: Array[Dictionary] = []
var _node_at: Dictionary = {}
var _cluster_nodes: Array = []
var _route_cache: Dictionary = {}
var _route_cache_order: Array[Vector2i] = [] # FIFO, cheap cache hits.


class _Heap:
	var keys := PackedFloat64Array()
	var vals := PackedInt32Array()

	func is_empty() -> bool:
		return vals.is_empty()

	func push(key: float, val: int) -> void:
		keys.append(key)
		vals.append(val)
		var i: int = vals.size() - 1
		while i > 0:
			var p: int = (i - 1) >> 1
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top: int = vals[0]
		var last: int = vals.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i := 0
		while true:
			var l: int = i * 2 + 1
			var r: int = l + 1
			var m: int = i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k: float = keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var v: int = vals[a]
		vals[a] = vals[b]
		vals[b] = v


## Builds clusters, entrance nodes and the abstract graph. walkable.call(x, y) -> bool.
func build(w: int, h: int, cluster: int, walkable: Callable) -> void:
	width = w
	height = h
	cluster_size = maxi(2, cluster)
	_walkable = walkable
	_cw = ceili(float(w) / cluster_size)
	_ch = ceili(float(h) / cluster_size)
	_grid.resize(w * h)
	for y in h:
		for x in w:
			_grid[y * w + x] = 1 if walkable.call(x, y) else 0
	_n_cell.clear()
	_n_cluster.clear()
	_n_alive.clear()
	_adj.clear()
	_node_at.clear()
	_route_cache.clear()
	_route_cache_order.clear()
	cache_hits = 0
	_cluster_nodes = []
	for i in _cw * _ch:
		_cluster_nodes.append([])
	for cy in _ch:
		for cx in _cw:
			if cx + 1 < _cw:
				_link_pair(Vector2i(cx, cy), Vector2i(cx + 1, cy))
			if cy + 1 < _ch:
				_link_pair(Vector2i(cx, cy), Vector2i(cx, cy + 1))
	for cy in _ch:
		for cx in _cw:
			_build_intra(Vector2i(cx, cy))


## Finds a 4-connected path of grid cells (start and goal included); empty when unreachable.
func find_path(start: Vector2i, goal: Vector2i) -> PackedVector2Array:
	if not _is_walkable(start) or not _is_walkable(goal):
		return PackedVector2Array()
	if start == goal:
		return PackedVector2Array([Vector2(start)])
	var sc := _cluster_of(start)
	var gc := _cluster_of(goal)
	if sc == gc:
		var direct := _astar(start, goal, _cluster_rect(sc))
		if not direct.is_empty():
			return direct
	var start_edges := _reach(start, sc)
	var goal_costs := _reach(goal, gc)
	if start_edges.is_empty() or goal_costs.is_empty():
		return PackedVector2Array()
	var key := Vector2i(_cidx(sc), _cidx(gc))
	var route := PackedInt32Array()
	if _route_cache.has(key):
		var cached: PackedInt32Array = _route_cache[key]
		if _route_ok(cached, start_edges, goal_costs):
			route = cached
			cache_hits += 1
	if route.is_empty():
		route = _abstract(start, goal, start_edges, goal_costs)
		if route.is_empty():
			return PackedVector2Array()
		# Reusing the same cluster-pair key can replace an inaccessible
		# corridor. Keep exactly one FIFO record for each retained key.
		if _route_cache.has(key):
			_route_cache_order.erase(key)
		elif _route_cache.size() >= MAX_CACHED_ROUTES:
			var evicted: Vector2i = _route_cache_order.pop_front()
			_route_cache.erase(evicted)
		_route_cache[key] = route
		_route_cache_order.append(key)
	return _refine(start, goal, route)


## Rebuilds only the cluster containing `cell` (and its border entrances) after the
## walkability of cells inside it changed.
func invalidate_cluster(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return
	var c := _cluster_of(cell)
	var rect := _cluster_rect(c)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_grid[y * width + x] = 1 if _walkable.call(x, y) else 0
	_route_cache.clear()
	_route_cache_order.clear()
	var neighbors: Array[Vector2i] = []
	for d in DIRS:
		var n := c + d
		if n.x >= 0 and n.y >= 0 and n.x < _cw and n.y < _ch:
			neighbors.append(n)
	var own: Array = _cluster_nodes[_cidx(c)].duplicate()
	for id: int in own:
		_remove_node(id)
	for n in neighbors:
		var ours: Array = _cluster_nodes[_cidx(n)].duplicate()
		for id: int in ours:
			if not _has_inter_edge(id):
				_remove_node(id)
	for n in neighbors:
		_link_pair(c, n)
	_build_intra(c)
	for n in neighbors:
		_build_intra(n)


## Resident abstract corridors are bounded even after long navigation sessions.
func cached_route_count() -> int:
	return _route_cache.size()


## Number of live abstract nodes (for tests and debug overlays).
func node_count() -> int:
	var total := 0
	for i in _n_alive.size():
		total += _n_alive[i]
	return total


func _is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	return _grid[cell.y * width + cell.x] == 1


func _cluster_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / cluster_size), floori(float(cell.y) / cluster_size))


func _cidx(c: Vector2i) -> int:
	return c.y * _cw + c.x


func _cluster_rect(c: Vector2i) -> Rect2i:
	var pos := c * cluster_size
	return Rect2i(pos, Vector2i(mini(cluster_size, width - pos.x), mini(cluster_size, height - pos.y)))


func _add_node(cell: Vector2i) -> int:
	if _node_at.has(cell):
		return _node_at[cell]
	var id: int = _n_cell.size()
	var c := _cluster_of(cell)
	_n_cell.append(cell)
	_n_cluster.append(_cidx(c))
	_n_alive.append(1)
	_adj.append({})
	_node_at[cell] = id
	_cluster_nodes[_cidx(c)].append(id)
	return id


func _remove_node(id: int) -> void:
	if _n_alive[id] == 0:
		return
	for k in _adj[id].keys():
		var other: int = k
		_adj[other].erase(id)
	_adj[id].clear()
	_n_alive[id] = 0
	_node_at.erase(_n_cell[id])
	_cluster_nodes[_n_cluster[id]].erase(id)


func _has_inter_edge(id: int) -> bool:
	for k in _adj[id].keys():
		var other: int = k
		if _n_cluster[other] != _n_cluster[id]:
			return true
	return false


## Places entrance node pairs along the border shared by two 4-adjacent clusters.
func _link_pair(a: Vector2i, b: Vector2i) -> void:
	if b.x < a.x or b.y < a.y:
		var t := a
		a = b
		b = t
	var ra := _cluster_rect(a)
	var horizontal: bool = b.x > a.x
	var from_cells: Array[Vector2i] = []
	var to_cells: Array[Vector2i] = []
	if horizontal:
		for y in range(ra.position.y, ra.end.y):
			from_cells.append(Vector2i(ra.end.x - 1, y))
			to_cells.append(Vector2i(ra.end.x, y))
	else:
		for x in range(ra.position.x, ra.end.x):
			from_cells.append(Vector2i(x, ra.end.y - 1))
			to_cells.append(Vector2i(x, ra.end.y))
	var run_start := -1
	for i in from_cells.size() + 1:
		var open: bool = i < from_cells.size() and _is_walkable(from_cells[i]) and _is_walkable(to_cells[i])
		if open and run_start < 0:
			run_start = i
		elif not open and run_start >= 0:
			var run_end: int = i - 1
			var picks: Array[int] = [(run_start + run_end) >> 1]
			if run_end - run_start + 1 > LONG_RUN:
				picks = [run_start, run_end]
			for p in picks:
				var na := _add_node(from_cells[p])
				var nb := _add_node(to_cells[p])
				_adj[na][nb] = 1
				_adj[nb][na] = 1
			run_start = -1


## Recomputes intra-cluster edges between all entrance nodes of one cluster.
func _build_intra(c: Vector2i) -> void:
	var ids: Array = _cluster_nodes[_cidx(c)]
	var rect := _cluster_rect(c)
	for id: int in ids:
		var keep := {}
		for k in _adj[id].keys():
			var other: int = k
			if _n_cluster[other] != _n_cluster[id]:
				keep[other] = _adj[id][other]
		_adj[id] = keep
	for id: int in ids:
		var dist := _flood(_n_cell[id], rect)
		for other: int in ids:
			if other == id:
				continue
			var key: int = _n_cell[other].y * width + _n_cell[other].x
			if dist.has(key):
				_adj[id][other] = dist[key]


## BFS distances (cell index -> steps) from a cell inside a rectangle.
func _flood(from: Vector2i, rect: Rect2i) -> Dictionary:
	var dist := {}
	var queue := PackedInt32Array([from.y * width + from.x])
	dist[queue[0]] = 0
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % width
		var cy: int = cur / width
		var d: int = dist[cur]
		for dir in DIRS:
			var n := Vector2i(cx, cy) + dir
			if not rect.has_point(n) or not _is_walkable(n):
				continue
			var ni: int = n.y * width + n.x
			if dist.has(ni):
				continue
			dist[ni] = d + 1
			queue.append(ni)
	return dist


## Node id -> steps for every entrance node of the cluster reachable from `cell` inside it.
func _reach(cell: Vector2i, c: Vector2i) -> Dictionary:
	var dist := _flood(cell, _cluster_rect(c))
	var out := {}
	for id: int in _cluster_nodes[_cidx(c)]:
		var key: int = _n_cell[id].y * width + _n_cell[id].x
		if dist.has(key):
			out[id] = dist[key]
	return out


func _route_ok(route: PackedInt32Array, start_edges: Dictionary, goal_costs: Dictionary) -> bool:
	if route.is_empty() or not start_edges.has(route[0]) or not goal_costs.has(route[route.size() - 1]):
		return false
	for i in route.size():
		if _n_alive[route[i]] == 0:
			return false
		if i > 0 and not _adj[route[i - 1]].has(route[i]):
			return false
	return true


func _abstract(start: Vector2i, goal: Vector2i, start_edges: Dictionary, goal_costs: Dictionary) -> PackedInt32Array:
	var g := {}
	var came := {}
	var closed := {}
	var heap := _Heap.new()
	for k in start_edges.keys():
		var n: int = k
		var cost: int = start_edges[n]
		g[n] = cost
		came[n] = -1
		heap.push(cost + _manhattan(_n_cell[n], goal), n)
	while not heap.is_empty():
		var cur: int = heap.pop()
		if cur == -2:
			break
		if closed.has(cur):
			continue
		closed[cur] = true
		var gc: int = g[cur]
		if goal_costs.has(cur):
			var total: int = gc + int(goal_costs[cur])
			var best: int = g.get(-2, FAR)
			if total < best:
				g[-2] = total
				came[-2] = cur
				heap.push(total, -2)
		for k in _adj[cur].keys():
			var to: int = k
			var ng: int = gc + int(_adj[cur][to])
			var old: int = g.get(to, FAR)
			if ng < old:
				g[to] = ng
				came[to] = cur
				heap.push(ng + _manhattan(_n_cell[to], goal), to)
	var route := PackedInt32Array()
	if not came.has(-2):
		return route
	var n: int = came[-2]
	while n != -1:
		route.append(n)
		n = came[n]
	route.reverse()
	return route


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Plain A* restricted to a rectangle (inside one cluster, or the whole grid).
func _astar(start: Vector2i, goal: Vector2i, rect: Rect2i) -> PackedVector2Array:
	var g := {}
	var came := {}
	var closed := {}
	var heap := _Heap.new()
	var si: int = start.y * width + start.x
	g[si] = 0
	heap.push(_manhattan(start, goal), si)
	var gi: int = goal.y * width + goal.x
	while not heap.is_empty():
		var cur: int = heap.pop()
		if cur == gi:
			var out := PackedVector2Array()
			var n: int = gi
			while n != si:
				out.append(Vector2(n % width, n / width))
				n = came[n]
			out.append(Vector2(start))
			out.reverse()
			return out
		if closed.has(cur):
			continue
		closed[cur] = true
		var cell := Vector2i(cur % width, cur / width)
		var cg: int = g[cur]
		for dir in DIRS:
			var nb := cell + dir
			if not rect.has_point(nb) or not _is_walkable(nb):
				continue
			var ni: int = nb.y * width + nb.x
			var old: int = g.get(ni, FAR)
			if cg + 1 < old:
				g[ni] = cg + 1
				came[ni] = cur
				heap.push(cg + 1 + _manhattan(nb, goal), ni)
	return PackedVector2Array()


func _append_segment(path: PackedVector2Array, seg: PackedVector2Array) -> bool:
	if seg.is_empty():
		return false
	for i in seg.size():
		if i == 0 and not path.is_empty() and path[path.size() - 1] == seg[0]:
			continue
		path.append(seg[i])
	return true


func _refine(start: Vector2i, goal: Vector2i, route: PackedInt32Array) -> PackedVector2Array:
	var path := PackedVector2Array()
	var first: Vector2i = _n_cell[route[0]]
	if not _append_segment(path, _astar(start, first, _cluster_rect(_cluster_of(start)))):
		return PackedVector2Array()
	for i in range(1, route.size()):
		var a: int = route[i - 1]
		var b: int = route[i]
		var seg: PackedVector2Array
		if _n_cluster[a] == _n_cluster[b]:
			var rect := _cluster_rect(_cluster_of(_n_cell[a]))
			seg = _astar(_n_cell[a], _n_cell[b], rect)
		else:
			seg = PackedVector2Array([Vector2(_n_cell[a]), Vector2(_n_cell[b])])
		if not _append_segment(path, seg):
			return PackedVector2Array()
	var last: Vector2i = _n_cell[route[route.size() - 1]]
	if not _append_segment(path, _astar(last, goal, _cluster_rect(_cluster_of(goal)))):
		return PackedVector2Array()
	return path
