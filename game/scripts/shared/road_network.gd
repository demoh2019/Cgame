extends RefCounted
## Road graph between sites: Delaunay edges -> Kruskal minimum spanning tree
## plus a fraction of the remaining short edges as loops.
##
## Technique: the Delaunay-triangulation + MST + extra-edges road/dungeon
## layout (e.g. the "Prim/Kruskal over Delaunay then re-add ~15% edges" recipe
## from Vazgriz's dungeon generator write-up, itself after TinyKeep). Written
## from the published algorithm description; no code copied. Kruskal with
## union-find is textbook (Kruskal 1956). Triangulation uses Godot's
## Geometry2D.triangulate_delaunay.
## Reference: https://vazgriz.com/119/procedurally-generated-dungeons/ (idea only).

@warning_ignore_start("integer_division")

const SAMPLE_STEP := 4.0


## Returns edges [{"a": int, "b": int, "length": float}]. The first n-1 entries
## are the minimum spanning tree (acyclic, connects all sites); any further
## entries are loop edges.
static func connect_sites(sites: PackedVector2Array, extra_edge_ratio: float = 0.15, seed: int = 0) -> Array:
	var n: int = sites.size()
	var result: Array = []
	if n < 2:
		return result
	var candidates: Array = _delaunay_edges(sites)
	var mst: Array = _kruskal(n, candidates)
	if mst.size() < n - 1:
		# Degenerate input (collinear / duplicate sites): fall back to all pairs.
		candidates = _all_edges(sites)
		mst = _kruskal(n, candidates)
	var in_mst: Dictionary = {}
	for e in mst:
		var ed: Dictionary = e
		in_mst[_key(ed["a"], ed["b"], n)] = true
	var rest: Array = []
	for e in candidates:
		var ed: Dictionary = e
		if not in_mst.has(_key(ed["a"], ed["b"], n)):
			rest.append(ed)
	rest.sort_custom(_by_length)
	result.append_array(mst)
	var want: int = int(round(clampf(extra_edge_ratio, 0.0, 1.0) * float(rest.size())))
	if want > 0:
		# Pick randomly (seeded) among the shorter half so loops stay local.
		var pool_size: int = clampi(maxi(want, (rest.size() + 1) / 2), 1, rest.size())
		var pool: Array = rest.slice(0, pool_size)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for i in range(pool.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Variant = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		for i in mini(want, pool.size()):
			result.append(pool[i])
	return result


## Travel cost of a straight road from a to b: length scaled up by slope.
## height_at is Callable(Vector2) -> float. Each metre of climb adds
## slope_penalty metres of effective length.
static func route_cost(a: Vector2, b: Vector2, height_at: Callable, slope_penalty: float) -> float:
	var dist: float = a.distance_to(b)
	if dist <= 0.0001:
		return 0.0
	var steps: int = maxi(1, int(ceil(dist / SAMPLE_STEP)))
	var cost: float = 0.0
	var prev: Vector2 = a
	var prev_h: float = float(height_at.call(a))
	for i in range(1, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		var ph: float = float(height_at.call(p))
		cost += prev.distance_to(p) + slope_penalty * absf(ph - prev_h)
		prev = p
		prev_h = ph
	return cost


static func _by_length(x: Dictionary, y: Dictionary) -> bool:
	var lx: float = x["length"]
	var ly: float = y["length"]
	if lx == ly:
		var ax: int = x["a"]
		var ay: int = y["a"]
		if ax != ay:
			return ax < ay
		var bx: int = x["b"]
		var by: int = y["b"]
		return bx < by
	return lx < ly


static func _key(a: int, b: int, n: int) -> int:
	return mini(a, b) * n + maxi(a, b)


static func _make_edge(sites: PackedVector2Array, a: int, b: int) -> Dictionary:
	return {"a": mini(a, b), "b": maxi(a, b), "length": sites[a].distance_to(sites[b])}


static func _delaunay_edges(sites: PackedVector2Array) -> Array:
	var n: int = sites.size()
	var seen: Dictionary = {}
	var out: Array = []
	var tris: PackedInt32Array = Geometry2D.triangulate_delaunay(sites)
	var t: int = 0
	while t + 2 < tris.size():
		for k in 3:
			var a: int = tris[t + k]
			var b: int = tris[t + (k + 1) % 3]
			var key: int = _key(a, b, n)
			if a != b and not seen.has(key):
				seen[key] = true
				out.append(_make_edge(sites, a, b))
		t += 3
	if n == 2 and out.is_empty():
		out.append(_make_edge(sites, 0, 1))
	return out


static func _all_edges(sites: PackedVector2Array) -> Array:
	var out: Array = []
	for a in sites.size():
		for b in range(a + 1, sites.size()):
			out.append(_make_edge(sites, a, b))
	return out


static func _find(parent: PackedInt32Array, i: int) -> int:
	var r: int = i
	while parent[r] != r:
		parent[r] = parent[parent[r]]
		r = parent[r]
	return r


static func _kruskal(n: int, edges: Array) -> Array:
	var sorted: Array = edges.duplicate()
	sorted.sort_custom(_by_length)
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var out: Array = []
	for e in sorted:
		var ed: Dictionary = e
		var ra: int = _find(parent, ed["a"])
		var rb: int = _find(parent, ed["b"])
		if ra != rb:
			parent[ra] = rb
			out.append(ed)
			if out.size() == n - 1:
				break
	return out
