extends RefCounted
## Dynamic navmesh obstacle carving with a budgeted tile cache.
##
## Concepts ported from Recast & Detour (DetourTileCache: obstacles queued per
## tile, tiles rebuilt incrementally under a per-update budget, rebuilt tiles
## re-linked to neighbours) and from Mikko Mononen's "simple stupid funnel"
## string pulling (DetourNavMeshQuery::findStraightPath).
## Recast Navigation, Copyright (c) 2009-2010 Mikko Mononen, zlib license.
## This is an independent 2D GDScript implementation, not a line-by-line copy.
## Polygon clipping/decomposition uses Godot's Geometry2D (MIT).
##
## Walkable space is a grid of tiles; each tile holds convex polygons.
## Obstacles (polygons or circles, grown by the agent radius) are subtracted
## from the tiles they touch. Destroying an obstacle (barricade, wall) re-carves
## only those tiles, reopening routes, and reports them in the change events so
## AI can repath.

const EPS := 0.002

var bounds := Rect2()
var tile_size := 10.0
var agent_radius := 0.5
var version := 0
var tiles_rebuilt_total := 0

var _tiles_x := 0
var _tiles_y := 0
var _base: Dictionary = {}  # Vector2i -> Array[PackedVector2Array]
var _tile_nodes: Dictionary = {}  # Vector2i -> PackedInt32Array
var _tile_version: Dictionary = {}  # Vector2i -> int
var _node_poly: Dictionary = {}  # int -> PackedVector2Array
var _node_rect: Dictionary = {}  # int -> Rect2
var _node_tile: Dictionary = {}  # int -> Vector2i
var _links: Dictionary = {}  # int -> Array of {to:int, a:Vector2, b:Vector2}
var _next_node := 1
var _obstacles: Dictionary = {}  # id -> {carvers: Array, rect: Rect2}
var _dirty: Array[Vector2i] = []
var _dirty_set: Dictionary = {}
var _events: Array[Vector2i] = []


func setup(p_bounds: Rect2, p_tile_size: float, p_agent_radius: float) -> void:
	bounds = p_bounds
	tile_size = maxf(p_tile_size, 1.0)
	agent_radius = maxf(p_agent_radius, 0.0)
	_tiles_x = maxi(1, ceili(bounds.size.x / tile_size))
	_tiles_y = maxi(1, ceili(bounds.size.y / tile_size))
	_clear_nodes()
	_base.clear()
	for ty in _tiles_y:
		for tx in _tiles_x:
			var t := Vector2i(tx, ty)
			var polys: Array[PackedVector2Array] = [_rect_poly(_tile_rect(t))]
			_base[t] = polys
	_rebuild_all()


## Restrict walkable space to the given polygons (clipped into tiles).
func set_walkable(polys: Array) -> void:
	_clear_nodes()
	for ty in _tiles_y:
		for tx in _tiles_x:
			var t := Vector2i(tx, ty)
			var rect_poly := _rect_poly(_tile_rect(t))
			var out: Array[PackedVector2Array] = []
			for p in polys:
				var poly: PackedVector2Array = p
				var res: Array[PackedVector2Array] = Geometry2D.intersect_polygons(poly, rect_poly)
				for r in res:
					if not Geometry2D.is_polygon_clockwise(r) and _area(r) > EPS:
						out.append(r)
			_base[t] = out
	_rebuild_all()


## shape: PackedVector2Array polygon, or {center: Vector2, radius: float, segments: int}.
func add_obstacle(id: Variant, shape: Variant) -> void:
	if _obstacles.has(id):
		remove_obstacle(id)
	var carvers: Array = _make_carvers(shape)
	if carvers.is_empty():
		return
	var rect := Rect2()
	var first := true
	for c in carvers:
		var cv: PackedVector2Array = c
		var b := _bounds_of(cv)
		rect = b if first else rect.merge(b)
		first = false
	_obstacles[id] = {"carvers": carvers, "rect": rect}
	_mark_rect_dirty(rect)


func remove_obstacle(id: Variant) -> bool:
	if not _obstacles.has(id):
		return false
	var ob: Dictionary = _obstacles[id]
	var rect: Rect2 = ob["rect"]
	_obstacles.erase(id)
	_mark_rect_dirty(rect)
	return true


## Destruction hook: a broken barricade/wall stops blocking the navmesh.
func on_destroyed(id: Variant) -> bool:
	return remove_obstacle(id)


func has_obstacle(id: Variant) -> bool:
	return _obstacles.has(id)


func pending_tiles() -> int:
	return _dirty.size()


## Re-carves up to max_tiles_per_call dirty tiles (<= 0 means all). Returns tiles rebuilt.
func update(max_tiles_per_call: int = 4) -> int:
	var done := 0
	while not _dirty.is_empty() and (max_tiles_per_call <= 0 or done < max_tiles_per_call):
		var t: Vector2i = _dirty.pop_front()
		_dirty_set.erase(t)
		_rebuild_tile(t)
		_events.append(t)
		done += 1
	if done > 0:
		version += 1
	return done


## Tiles rebuilt since the last call (AI repath notifications).
func consume_changed_tiles() -> Array[Vector2i]:
	var out := _events.duplicate()
	_events.clear()
	return out


func tile_version(tile: Vector2i) -> int:
	return int(_tile_version.get(tile, 0))


func tile_count() -> Vector2i:
	return Vector2i(_tiles_x, _tiles_y)


func tile_of(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - bounds.position.x) / tile_size), floori((point.y - bounds.position.y) / tile_size))


func polygons_in_tile(tile: Vector2i) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not _tile_nodes.has(tile):
		return out
	var ids: PackedInt32Array = _tile_nodes[tile]
	for n in ids:
		out.append(_node_poly[n])
	return out


func is_walkable(point: Vector2) -> bool:
	return _node_at(point) != 0


static func is_convex(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var sign_seen := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var c := poly[(i + 2) % n]
		var cr := (b - a).cross(c - b)
		if absf(cr) < 1.0e-6:
			continue
		if sign_seen == 0.0:
			sign_seen = signf(cr)
		elif signf(cr) != sign_seen:
			return false
	return true


## A* over polygons, then funnel string pulling. Empty when either end is blocked or unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var sn := _node_at(from)
	var en := _node_at(to)
	if sn == 0 or en == 0:
		return PackedVector2Array()
	if sn == en:
		return PackedVector2Array([from, to])
	var g: Dictionary = {sn: 0.0}
	var pos: Dictionary = {sn: from}
	var came: Dictionary = {}
	var open: Array[int] = [sn]
	var closed: Dictionary = {}
	var found := false
	while not open.is_empty():
		var bi := 0
		var bf := INF
		for i in open.size():
			var n: int = open[i]
			var p: Vector2 = pos[n]
			var f := float(g[n]) + p.distance_to(to)
			if f < bf:
				bf = f
				bi = i
		var cur: int = open[bi]
		open.remove_at(bi)
		if cur == en:
			found = true
			break
		closed[cur] = true
		var cur_pos: Vector2 = pos[cur]
		var links: Array = _links.get(cur, [])
		for lk in links:
			var link: Dictionary = lk
			var nb: int = link["to"]
			if closed.has(nb):
				continue
			var la: Vector2 = link["a"]
			var lb: Vector2 = link["b"]
			var mid := (la + lb) * 0.5
			var ng := float(g[cur]) + cur_pos.distance_to(mid)
			if not g.has(nb) or ng < float(g[nb]):
				g[nb] = ng
				pos[nb] = mid
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	if not found:
		return PackedVector2Array()
	var corridor: Array[int] = [en]
	var walk := en
	while came.has(walk):
		walk = came[walk]
		corridor.push_front(walk)
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	for i in corridor.size() - 1:
		var from_n: int = corridor[i]
		var to_n: int = corridor[i + 1]
		var link := _link_between(from_n, to_n)
		var c := _centroid(_node_poly[from_n])
		var pa: Vector2 = link["a"]
		var pb: Vector2 = link["b"]
		if (pa - c).cross(pb - c) < 0.0:
			lefts.append(pa)
			rights.append(pb)
		else:
			lefts.append(pb)
			rights.append(pa)
	return _funnel(from, to, lefts, rights)


## True when any segment of the path passes through one of the changed tiles.
func path_affected(path: PackedVector2Array, changed: Array[Vector2i]) -> bool:
	if changed.is_empty():
		return false
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / (tile_size * 0.5)))
		for s in steps + 1:
			if changed.has(tile_of(a.lerp(b, float(s) / float(steps)))):
				return true
	return false


# ---------------------------------------------------------------- internals

func _clear_nodes() -> void:
	_tile_nodes.clear()
	_node_poly.clear()
	_node_rect.clear()
	_node_tile.clear()
	_links.clear()
	_dirty.clear()
	_dirty_set.clear()
	_events.clear()


func _rebuild_all() -> void:
	for ty in _tiles_y:
		for tx in _tiles_x:
			_rebuild_tile(Vector2i(tx, ty))
	tiles_rebuilt_total = 0
	_tile_version.clear()


func _tile_rect(t: Vector2i) -> Rect2:
	return Rect2(bounds.position + Vector2(t) * tile_size, Vector2(tile_size, tile_size))


func _mark_rect_dirty(rect: Rect2) -> void:
	var lo := tile_of(rect.position - Vector2(EPS, EPS))
	var hi := tile_of(rect.end + Vector2(EPS, EPS))
	for ty in range(maxi(lo.y, 0), mini(hi.y, _tiles_y - 1) + 1):
		for tx in range(maxi(lo.x, 0), mini(hi.x, _tiles_x - 1) + 1):
			var t := Vector2i(tx, ty)
			if not _dirty_set.has(t):
				_dirty_set[t] = true
				_dirty.append(t)


func _make_carvers(shape: Variant) -> Array:
	var out: Array = []
	if shape is Dictionary:
		var d: Dictionary = shape
		var center: Vector2 = d.get("center", Vector2.ZERO)
		var radius: float = float(d.get("radius", 1.0)) + agent_radius
		var segs: int = maxi(int(d.get("segments", 12)), 6)
		var rr := radius / cos(PI / float(segs))  # circumscribed so the polygon covers the circle
		var poly := PackedVector2Array()
		for i in segs:
			var ang := TAU * float(i) / float(segs)
			poly.append(center + Vector2(cos(ang), sin(ang)) * rr)
		out.append(poly)
	elif shape is PackedVector2Array:
		var src: PackedVector2Array = shape
		if src.size() < 3:
			return out
		if agent_radius > 0.0:
			var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(src, agent_radius, Geometry2D.JOIN_MITER)
			for g in grown:
				if not Geometry2D.is_polygon_clockwise(g):
					out.append(g)
		else:
			out.append(src)
	return out


func _rebuild_tile(t: Vector2i) -> void:
	_remove_tile_nodes(t)
	var base: Array[PackedVector2Array] = _base[t]
	var polys: Array[PackedVector2Array] = []
	polys.append_array(base)
	var rect := _tile_rect(t).grow(EPS)
	for id in _obstacles:
		var ob: Dictionary = _obstacles[id]
		var orect: Rect2 = ob["rect"]
		if not orect.intersects(rect):
			continue
		var carvers: Array = ob["carvers"]
		for c in carvers:
			var cv: PackedVector2Array = c
			polys = _subtract(polys, cv)
		if polys.is_empty():
			break
	var ids := PackedInt32Array()
	for p in polys:
		var pieces: Array[PackedVector2Array] = []
		if is_convex(p):
			pieces.append(p)
		else:
			pieces = Geometry2D.decompose_polygon_in_convex(p)
		for piece in pieces:
			if piece.size() < 3 or _area(piece) < EPS:
				continue
			var nid := _next_node
			_next_node += 1
			_node_poly[nid] = piece
			_node_rect[nid] = _bounds_of(piece)
			_node_tile[nid] = t
			_links[nid] = []
			ids.append(nid)
	_tile_nodes[t] = ids
	_tile_version[t] = tile_version(t) + 1
	tiles_rebuilt_total += 1
	# Re-link the new nodes against this tile and its 8 neighbours.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nt := t + Vector2i(dx, dy)
			if not _tile_nodes.has(nt):
				continue
			var others: PackedInt32Array = _tile_nodes[nt]
			for a in ids:
				for b in others:
					if nt != t or a < b:
						_try_link(a, b)


func _remove_tile_nodes(t: Vector2i) -> void:
	if not _tile_nodes.has(t):
		return
	var ids: PackedInt32Array = _tile_nodes[t]
	for n in ids:
		var links: Array = _links.get(n, [])
		for lk in links:
			var link: Dictionary = lk
			var other: int = link["to"]
			if not _links.has(other):
				continue
			var back: Array = _links[other]
			for i in range(back.size() - 1, -1, -1):
				var bl: Dictionary = back[i]
				if int(bl["to"]) == n:
					back.remove_at(i)
		_links.erase(n)
		_node_poly.erase(n)
		_node_rect.erase(n)
		_node_tile.erase(n)
	_tile_nodes[t] = PackedInt32Array()


func _try_link(a: int, b: int) -> void:
	var ra: Rect2 = _node_rect[a]
	var rb: Rect2 = _node_rect[b]
	if not ra.grow(EPS * 4.0).intersects(rb):
		return
	var pa: PackedVector2Array = _node_poly[a]
	var pb: PackedVector2Array = _node_poly[b]
	for i in pa.size():
		var a0 := pa[i]
		var a1 := pa[(i + 1) % pa.size()]
		var seg_len := a0.distance_to(a1)
		if seg_len < EPS:
			continue
		var d := (a1 - a0) / seg_len
		for j in pb.size():
			var b0 := pb[j]
			var b1 := pb[(j + 1) % pb.size()]
			if absf(d.cross(b0 - a0)) > EPS or absf(d.cross(b1 - a0)) > EPS:
				continue
			var tb0 := d.dot(b0 - a0)
			var tb1 := d.dot(b1 - a0)
			var lo := maxf(0.0, minf(tb0, tb1))
			var hi := minf(seg_len, maxf(tb0, tb1))
			if hi - lo > 0.01:
				var la := a0 + d * lo
				var lb := a0 + d * hi
				var l_ab: Array = _links[a]
				var l_ba: Array = _links[b]
				l_ab.append({"to": b, "a": la, "b": lb})
				l_ba.append({"to": a, "a": la, "b": lb})
				return


func _link_between(a: int, b: int) -> Dictionary:
	var links: Array = _links[a]
	for lk in links:
		var link: Dictionary = lk
		if int(link["to"]) == b:
			return link
	return {}


func _node_at(point: Vector2) -> int:
	var t := tile_of(point)
	if not _tile_nodes.has(t):
		return 0
	var ids: PackedInt32Array = _tile_nodes[t]
	for n in ids:
		var r: Rect2 = _node_rect[n]
		if r.grow(EPS).has_point(point) and _inside(_node_poly[n], point):
			return n
	return 0


static func _inside(poly: PackedVector2Array, p: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(p, poly):
		return true
	# Boundary counts as walkable.
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < EPS:
			return true
	return false


## Subtracts one carver from every polygon. Result polygons are outer rings only (holes are
## avoided by splitting the polygon through the carver before clipping).
func _subtract(polys: Array[PackedVector2Array], carver: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var cr := _bounds_of(carver)
	for p in polys:
		if not _bounds_of(p).grow(EPS).intersects(cr):
			out.append(p)
		else:
			_clip_into(p, carver, cr, out, 0)
	return out


func _clip_into(p: PackedVector2Array, carver: PackedVector2Array, cr: Rect2, out: Array[PackedVector2Array], depth: int) -> void:
	var res: Array[PackedVector2Array] = Geometry2D.clip_polygons(p, carver)
	var has_hole := false
	for r in res:
		if Geometry2D.is_polygon_clockwise(r):
			has_hole = true
	if not has_hole or depth >= 3:
		for r in res:
			if not Geometry2D.is_polygon_clockwise(r) and _area(r) > EPS:
				out.append(r)
		return
	# Hole: cut p in two through the carver's centre so neither half contains it entirely.
	var pb := _bounds_of(p).grow(1.0)
	var c := cr.get_center()
	var halves: Array[PackedVector2Array] = []
	if depth % 2 == 0:
		halves.append(_rect_poly(Rect2(pb.position, Vector2(c.x - pb.position.x, pb.size.y))))
		halves.append(_rect_poly(Rect2(Vector2(c.x, pb.position.y), Vector2(pb.end.x - c.x, pb.size.y))))
	else:
		halves.append(_rect_poly(Rect2(pb.position, Vector2(pb.size.x, c.y - pb.position.y))))
		halves.append(_rect_poly(Rect2(Vector2(pb.position.x, c.y), Vector2(pb.size.x, pb.end.y - c.y))))
	for h in halves:
		var parts: Array[PackedVector2Array] = Geometry2D.intersect_polygons(p, h)
		for part in parts:
			if not Geometry2D.is_polygon_clockwise(part) and _area(part) > EPS:
				_clip_into(part, carver, cr, out, depth + 1)


## "Simple stupid funnel" string pulling (Mikko Mononen, zlib), adapted to 2D y-down.
func _funnel(start: Vector2, goal: Vector2, lefts: PackedVector2Array, rights: PackedVector2Array) -> PackedVector2Array:
	var pl := PackedVector2Array([start])
	pl.append_array(lefts)
	pl.append(goal)
	var pr := PackedVector2Array([start])
	pr.append_array(rights)
	pr.append(goal)
	var out := PackedVector2Array([start])
	var apex := start
	var lft := start
	var rgt := start
	var apex_i := 0
	var left_i := 0
	var right_i := 0
	var i := 1
	var n := pl.size()
	var guard := 0
	while i < n and guard < n * n + 16:
		guard += 1
		var l := pl[i]
		var r := pr[i]
		if _tri2(apex, rgt, r) <= 0.0:
			if apex.is_equal_approx(rgt) or _tri2(apex, lft, r) > 0.0:
				rgt = r
				right_i = i
			else:
				out.append(lft)
				apex = lft
				apex_i = left_i
				lft = apex
				rgt = apex
				left_i = apex_i
				right_i = apex_i
				i = apex_i + 1
				continue
		if _tri2(apex, lft, l) >= 0.0:
			if apex.is_equal_approx(lft) or _tri2(apex, rgt, l) < 0.0:
				lft = l
				left_i = i
			else:
				out.append(rgt)
				apex = rgt
				apex_i = right_i
				lft = apex
				rgt = apex
				left_i = apex_i
				right_i = apex_i
				i = apex_i + 1
				continue
		i += 1
	if not out[out.size() - 1].is_equal_approx(goal):
		out.append(goal)
	return out


static func _tri2(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ax := b.x - a.x
	var ay := b.y - a.y
	var bx := c.x - a.x
	var by := c.y - a.y
	return bx * ay - ax * by


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _bounds_of(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(s) * 0.5


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(poly.size())
