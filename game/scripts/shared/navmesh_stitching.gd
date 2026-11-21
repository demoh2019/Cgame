extends RefCounted
## Tiled navmesh stitching (portal links between tiles), polygon graph and
## A* + Simple Stupid Funnel path smoothing.
##
## Concepts ported from Recast/Detour tiled navmeshes (tile border portals,
## polygon-corridor A*, string pulling):
##   https://github.com/recastnavigation/recastnavigation
##   Copyright (c) 2009-2010 Mikko Mononen, zlib license.
## Funnel algorithm after Mikko Mononen's "Simple Stupid Funnel Algorithm"
## write-up (https://digestingduck.blogspot.com/2010/03/simple-stupid-funnel-algorithm.html),
## re-implemented from the description, as also done in Detour's
## dtNavMeshQuery::findStraightPath. No GPL/LGPL code is used.
##
## Tiles: {"origin": Vector2, "size": float, "polygons": Array[PackedVector2Array]}.
## Orientation: travelling a -> b, "left" is the portal end with positive cross
## product relative to the travel direction (+y when heading +x).


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


## Orders a portal segment so that "left" is on the left of travel from
## from_c across the segment.
static func _orient(p1: Vector2, p2: Vector2, from_c: Vector2) -> Array:
	var mid: Vector2 = (p1 + p2) * 0.5
	var d: Vector2 = mid - from_c
	if _cross(d, p1 - mid) >= 0.0:
		return [p1, p2]
	return [p2, p1]


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(float(poly.size()), 1.0)


static func _tile_rect(t: Dictionary) -> Rect2:
	var o: Vector2 = t["origin"]
	var s: float = t["size"]
	return Rect2(o, Vector2(s, s))


## Finds polygon edges that lie on the border shared by two tiles and overlap
## along it. Returns [{"poly_a": int, "poly_b": int, "left": Vector2, "right": Vector2}].
static func stitch(tile_a: Dictionary, tile_b: Dictionary, tolerance: float) -> Array:
	var links: Array = []
	var ra: Rect2 = _tile_rect(tile_a)
	var rb: Rect2 = _tile_rect(tile_b)
	# axis 0: border is a vertical line (x const), edges run along y; axis 1: the reverse.
	for axis in 2:
		var a_hi: float = ra.end[axis]
		var b_lo: float = rb.position[axis]
		var a_lo: float = ra.position[axis]
		var b_hi: float = rb.end[axis]
		var border := 0.0
		if absf(a_hi - b_lo) <= tolerance:
			border = (a_hi + b_lo) * 0.5
		elif absf(b_hi - a_lo) <= tolerance:
			border = (b_hi + a_lo) * 0.5
		else:
			continue
		var other: int = 1 - axis
		# quick reject: must touch along the other axis
		if minf(ra.end[other], rb.end[other]) - maxf(ra.position[other], rb.position[other]) < -tolerance:
			continue
		var polys_a: Array = tile_a["polygons"]
		var polys_b: Array = tile_b["polygons"]
		for ia in polys_a.size():
			var pa: PackedVector2Array = polys_a[ia]
			var ca: Vector2 = _centroid(pa)
			for ea in pa.size():
				var a0: Vector2 = pa[ea]
				var a1: Vector2 = pa[(ea + 1) % pa.size()]
				if absf(a0[axis] - border) > tolerance or absf(a1[axis] - border) > tolerance:
					continue
				var amin: float = minf(a0[other], a1[other])
				var amax: float = maxf(a0[other], a1[other])
				for ib in polys_b.size():
					var pb: PackedVector2Array = polys_b[ib]
					for eb in pb.size():
						var b0: Vector2 = pb[eb]
						var b1: Vector2 = pb[(eb + 1) % pb.size()]
						if absf(b0[axis] - border) > tolerance or absf(b1[axis] - border) > tolerance:
							continue
						var lo: float = maxf(amin, minf(b0[other], b1[other]))
						var hi: float = minf(amax, maxf(b0[other], b1[other]))
						if hi - lo <= tolerance:
							continue
						var q0 := Vector2.ZERO
						var q1 := Vector2.ZERO
						q0[axis] = border
						q0[other] = lo
						q1[axis] = border
						q1[other] = hi
						var lr: Array = _orient(q0, q1, ca)
						links.append({"poly_a": ia, "poly_b": ib, "left": lr[0], "right": lr[1]})
	return links


static func _add_link(graph: Dictionary, from_i: int, to_i: int, p1: Vector2, p2: Vector2) -> void:
	var centers: PackedVector2Array = graph["centers"]
	var lr: Array = _orient(p1, p2, centers[from_i])
	var arr: Array = graph["links"][from_i]
	arr.append({"to": to_i, "left": lr[0], "right": lr[1]})


## Builds polygon adjacency across all tiles (intra-tile shared edges plus
## stitched tile borders). Graph: {"polys": Array, "centers": PackedVector2Array,
## "links": Array[Array[{to,left,right}]], "tile_of": PackedInt32Array, "offsets": PackedInt32Array}
static func build_graph(tiles: Array, tolerance: float) -> Dictionary:
	var polys: Array = []
	var centers := PackedVector2Array()
	var tile_of := PackedInt32Array()
	var offsets := PackedInt32Array()
	for ti in tiles.size():
		var t: Dictionary = tiles[ti]
		offsets.append(polys.size())
		for p in (t["polygons"] as Array):
			var poly: PackedVector2Array = p
			polys.append(poly)
			centers.append(_centroid(poly))
			tile_of.append(ti)
	var links: Array = []
	for i in polys.size():
		links.append([])
	var graph: Dictionary = {"polys": polys, "centers": centers, "links": links, "tile_of": tile_of, "offsets": offsets}
	# intra-tile adjacency: shared (reversed or equal) edges
	for ti in tiles.size():
		var off: int = offsets[ti]
		var tp: Array = (tiles[ti] as Dictionary)["polygons"]
		for i in tp.size():
			var pi: PackedVector2Array = tp[i]
			for j in range(i + 1, tp.size()):
				var pj: PackedVector2Array = tp[j]
				var found := false
				for ei in pi.size():
					if found:
						break
					var a0: Vector2 = pi[ei]
					var a1: Vector2 = pi[(ei + 1) % pi.size()]
					for ej in pj.size():
						var b0: Vector2 = pj[ej]
						var b1: Vector2 = pj[(ej + 1) % pj.size()]
						var rev: bool = a0.distance_to(b1) <= tolerance and a1.distance_to(b0) <= tolerance
						var same: bool = a0.distance_to(b0) <= tolerance and a1.distance_to(b1) <= tolerance
						if rev or same:
							_add_link(graph, off + i, off + j, a0, a1)
							_add_link(graph, off + j, off + i, a0, a1)
							found = true
							break
	# cross-tile portals
	for ta in tiles.size():
		for tb in range(ta + 1, tiles.size()):
			for l in stitch(tiles[ta], tiles[tb], tolerance):
				var link: Dictionary = l
				var ga: int = offsets[ta] + int(link["poly_a"])
				var gb: int = offsets[tb] + int(link["poly_b"])
				_add_link(graph, ga, gb, link["left"], link["right"])
				_add_link(graph, gb, ga, link["left"], link["right"])
	return graph


static func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


static func _locate(graph: Dictionary, p: Vector2) -> int:
	var polys: Array = graph["polys"]
	for i in polys.size():
		if _point_in_poly(p, polys[i]):
			return i
	var centers: PackedVector2Array = graph["centers"]
	var best := -1
	var best_d := INF
	for i in centers.size():
		var d: float = centers[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## A* over polygons (node position = entry portal midpoint) then funnel.
static func find_path(graph: Dictionary, start: Vector2, goal: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array()
	var si: int = _locate(graph, start)
	var gi: int = _locate(graph, goal)
	if si < 0 or gi < 0:
		return path
	if si == gi:
		path.append(start)
		path.append(goal)
		return path
	var links: Array = graph["links"]
	var g: Dictionary = {si: 0.0}
	var pos: Dictionary = {si: start}
	var parent: Dictionary = {}
	var parent_link: Dictionary = {}
	var open: Array = [si]
	var closed: Dictionary = {}
	var found := false
	while not open.is_empty():
		var bi := 0
		var bf := INF
		for oi in open.size():
			var n: int = open[oi]
			var np: Vector2 = pos[n]
			var f: float = float(g[n]) + np.distance_to(goal)
			if f < bf:
				bf = f
				bi = oi
		var cur: int = open[bi]
		open.remove_at(bi)
		if cur == gi:
			found = true
			break
		closed[cur] = true
		var cp: Vector2 = pos[cur]
		for l in (links[cur] as Array):
			var link: Dictionary = l
			var to: int = link["to"]
			if closed.has(to):
				continue
			var l0: Vector2 = link["left"]
			var l1: Vector2 = link["right"]
			var entry: Vector2 = (l0 + l1) * 0.5
			var cost: float = float(g[cur]) + cp.distance_to(entry)
			if to == gi:
				cost += entry.distance_to(goal) - 0.0
			if not g.has(to) or cost < float(g[to]):
				g[to] = cost
				pos[to] = entry
				parent[to] = cur
				parent_link[to] = link
				if not open.has(to):
					open.append(to)
	if not found:
		return path
	var chain: Array = []
	var n2: int = gi
	while n2 != si:
		chain.push_front(parent_link[n2])
		n2 = parent[n2]
	var portals: Array = [[start, start]]
	for l in chain:
		var link2: Dictionary = l
		portals.append([link2["left"], link2["right"]])
	portals.append([goal, goal])
	return funnel(portals)


static func _tri2(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ax: float = b.x - a.x
	var ay: float = b.y - a.y
	var bx: float = c.x - a.x
	var by: float = c.y - a.y
	return bx * ay - ax * by


## Simple Stupid Funnel. portals: Array of [left: Vector2, right: Vector2],
## first = [start, start], last = [goal, goal].
static func funnel(portals: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if portals.is_empty():
		return out
	var first: Array = portals[0]
	var apex: Vector2 = first[0]
	var left: Vector2 = first[0]
	var right: Vector2 = first[1]
	var apex_i := 0
	var left_i := 0
	var right_i := 0
	out.append(apex)
	var i := 1
	var guard := 0
	while i < portals.size() and guard < 10000:
		guard += 1
		var pr: Array = portals[i]
		var nl: Vector2 = pr[0]
		var nr: Vector2 = pr[1]
		# tighten right side
		if _tri2(apex, right, nr) <= 0.0:
			if apex.is_equal_approx(right) or _tri2(apex, left, nr) > 0.0:
				right = nr
				right_i = i
			else:
				out.append(left)
				apex = left
				apex_i = left_i
				left = apex
				right = apex
				left_i = apex_i
				right_i = apex_i
				i = apex_i + 1
				continue
		# tighten left side
		if _tri2(apex, left, nl) >= 0.0:
			if apex.is_equal_approx(left) or _tri2(apex, right, nl) < 0.0:
				left = nl
				left_i = i
			else:
				out.append(right)
				apex = right
				apex_i = right_i
				left = apex
				right = apex
				left_i = apex_i
				right_i = apex_i
				i = apex_i + 1
				continue
		i += 1
	var last: Array = portals[portals.size() - 1]
	var goal: Vector2 = last[0]
	if out.size() == 0 or not out[out.size() - 1].is_equal_approx(goal):
		out.append(goal)
	return out
