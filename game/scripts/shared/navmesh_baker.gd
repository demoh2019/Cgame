extends RefCounted
## Recast-style navmesh baker: triangle soup -> tiled convex-polygon navmesh.
##
## Pipeline ported from the algorithms of Recast (Recast Navigation):
##   https://github.com/recastnavigation/recastnavigation
##   Copyright (c) 2009-2010 Mikko Mononen memon@inf.ed.ac.uk, zlib license.
## Stages (re-implemented from the published algorithm descriptions, not
## copied verbatim; no GPL/LGPL code is used):
##   1. solid heightfield voxelization (rcRasterizeTriangles: per-cell polygon
##      clipping, span merge with walkable-flag priority by top height)
##   2. walkable span filtering: low hanging obstacles, ledge spans, low
##      clearance spans (rcFilter*)
##   3. compact open heightfield + 4-neighbour connectivity
##      (rcBuildCompactHeightfield) and agent-radius erosion through the
##      2/3-chamfer distance field (rcErodeWalkableArea)
##   4. monotone region partitioning (rcBuildRegionsMonotone)
##   5. region contour tracing (walkContour) + Douglas-Peucker simplification
##      that only tessellates wall edges (simplifyContour)
##   6. ear-clipping triangulation + greedy convex polygon merging with a
##      max-verts-per-poly limit (rcBuildPolyMesh)
## Tiling: every tile is voxelized with a border of (agent radius + 3 cells) so
## erosion and ledges behave identically on both sides of a tile edge; the
## resulting convex polygons are then clipped to the exact tile rectangle, so
## neighbouring tiles share border edges that scripts/shared/navmesh_stitching.gd
## can link into portals.
##
## Tile result: {"origin": Vector2 (xz), "size": float, "polygons":
## Array[PackedVector2Array] (xz, positive shoelace area, convex), "heights":
## Array[PackedFloat32Array] (world y per polygon vertex)}.
## Triangle winding: counter-clockwise seen from above (+y normal) is
## walkable-facing; downward-facing triangles act as ceilings.

const INF_H: int = 1 << 24
const DIR_X: Array[int] = [-1, 0, 1, 0]
const DIR_Z: Array[int] = [0, 1, 0, -1]

var config: Dictionary = {
	"cell_size": 0.3,
	"cell_height": 0.2,
	"agent_height": 2.0,
	"agent_radius": 0.5,
	"agent_max_climb": 0.4,
	"agent_max_slope_deg": 45.0,
	"region_min_area": 8,
	"max_verts_per_poly": 6,
	"tile_size": 16.0,
	"max_simplification_error": 1.3,
}

var _jobs: Dictionary = {}
var _next_job: int = 1
var _mutex: Mutex = Mutex.new()


## Per-bake working state (kept local to each bake so tiles can run on threads).
class Ctx:
	extends RefCounted
	var gw: int = 0
	var gh: int = 0
	var cs: float = 0.3
	var ch: float = 0.2
	var bmin: Vector3 = Vector3.ZERO
	var walk_h: int = 10
	var climb: int = 2
	var radius: int = 2
	var slope_cos: float = 0.7
	var cols: Array = []
	var n: int = 0
	var sx: PackedInt32Array = PackedInt32Array()
	var sz: PackedInt32Array = PackedInt32Array()
	var sy: PackedInt32Array = PackedInt32Array()
	var sh: PackedInt32Array = PackedInt32Array()
	var con: PackedInt32Array = PackedInt32Array()
	var col_start: PackedInt32Array = PackedInt32Array()
	var col_count: PackedInt32Array = PackedInt32Array()
	var reg: PackedInt32Array = PackedInt32Array()


func configure(values: Dictionary) -> void:
	config.merge(values, true)


func _cf(key: String) -> float:
	return float(config.get(key, 0.0))


func _ci(key: String) -> int:
	return int(config.get(key, 0))


# ---------------------------------------------------------------- public API

func bake_tile(triangles: PackedVector3Array, tile_bounds: AABB) -> Dictionary:
	var cs: float = _cf("cell_size")
	var chh: float = _cf("cell_height")
	var ctx := Ctx.new()
	ctx.cs = cs
	ctx.ch = chh
	ctx.walk_h = maxi(1, ceili(_cf("agent_height") / chh - 0.001))
	ctx.climb = maxi(0, floori(_cf("agent_max_climb") / chh + 0.001))
	ctx.radius = maxi(0, ceili(_cf("agent_radius") / cs - 0.001))
	ctx.slope_cos = cos(deg_to_rad(_cf("agent_max_slope_deg")))
	var border: int = ctx.radius + 3
	ctx.gw = ceili(tile_bounds.size.x / cs - 0.001) + border * 2
	ctx.gh = ceili(tile_bounds.size.z / cs - 0.001) + border * 2
	var result: Dictionary = {
		"origin": Vector2(tile_bounds.position.x, tile_bounds.position.z),
		"size": tile_bounds.size.x,
		"polygons": [] as Array[PackedVector2Array],
		"heights": [] as Array[PackedFloat32Array],
	}
	if ctx.gw <= 0 or ctx.gh <= 0 or ctx.gw * ctx.gh > 4000000:
		return result
	var bx: float = tile_bounds.position.x - border * cs
	var bz: float = tile_bounds.position.z - border * cs
	var by: float = tile_bounds.position.y
	if tile_bounds.size.y <= 0.0:
		by = _min_y(triangles, bx, bz, bx + ctx.gw * cs, bz + ctx.gh * cs)
	ctx.bmin = Vector3(bx, by, bz)
	ctx.cols = []
	ctx.cols.resize(ctx.gw * ctx.gh)
	for i in ctx.cols.size():
		ctx.cols[i] = PackedInt32Array()
	_rasterize(ctx, triangles)
	_filter(ctx)
	_build_compact_from_cols(ctx)
	_erode(ctx)
	_build_regions(ctx, _ci("region_min_area"))
	var raw_polys: Array = _build_polys(ctx, clampi(_ci("max_verts_per_poly"), 3, 12), _cf("max_simplification_error"))
	var rect := Rect2(tile_bounds.position.x, tile_bounds.position.z, tile_bounds.size.x, tile_bounds.size.z)
	var polys: Array[PackedVector2Array] = []
	var heights: Array[PackedFloat32Array] = []
	for rp in raw_polys:
		var clipped: PackedVector3Array = _clip_to_rect(rp as PackedVector3Array, rect)
		if clipped.size() < 3:
			continue
		var p2 := PackedVector2Array()
		var hs := PackedFloat32Array()
		for k in clipped.size():
			p2.append(Vector2(clipped[k].x, clipped[k].z))
			hs.append(clipped[k].y)
		if _signed_area(p2) < 1e-4:
			continue
		polys.append(p2)
		heights.append(hs)
	result["polygons"] = polys
	result["heights"] = heights
	return result


## Splits world_bounds into tile_size tiles and bakes each on the
## WorkerThreadPool. Returns a job id for poll().
func bake_async(triangles: PackedVector3Array, world_bounds: AABB) -> int:
	var job: int = _next_job
	_next_job += 1
	var rects: Array[AABB] = tile_rects(world_bounds)
	var results: Array = []
	results.resize(rects.size())
	var state: Dictionary = {"tasks": PackedInt32Array(), "results": results, "done": false, "tiles": []}
	_mutex.lock()
	_jobs[job] = state
	_mutex.unlock()
	var ids := PackedInt32Array()
	for i in rects.size():
		ids.append(WorkerThreadPool.add_task(_tile_task.bind(job, i, triangles, rects[i]), false, "navmesh tile"))
	state["tasks"] = ids
	return job


## {"done": bool, "tiles": Array[Dictionary]}; tiles are in row-major order
## (x fastest) and only filled once done.
func poll(job: int) -> Dictionary:
	_mutex.lock()
	var has_job: bool = _jobs.has(job)
	var state: Dictionary = _jobs[job] if has_job else {}
	_mutex.unlock()
	if not has_job:
		return {"done": true, "tiles": []}
	if bool(state["done"]):
		return {"done": true, "tiles": state["tiles"]}
	var ids: PackedInt32Array = state["tasks"]
	for id in ids:
		if not WorkerThreadPool.is_task_completed(id):
			return {"done": false, "tiles": []}
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_mutex.lock()
	var tiles: Array = (state["results"] as Array).duplicate()
	_mutex.unlock()
	state["done"] = true
	state["tiles"] = tiles
	return {"done": true, "tiles": tiles}


## Tile rectangles covering world_bounds (row-major, x fastest).
func tile_rects(world_bounds: AABB) -> Array[AABB]:
	var ts: float = maxf(_cf("tile_size"), 1.0)
	var nx: int = maxi(1, ceili(world_bounds.size.x / ts - 0.0001))
	var nz: int = maxi(1, ceili(world_bounds.size.z / ts - 0.0001))
	var rects: Array[AABB] = []
	for iz in nz:
		for ix in nx:
			rects.append(AABB(Vector3(world_bounds.position.x + ix * ts, world_bounds.position.y, world_bounds.position.z + iz * ts),
				Vector3(ts, world_bounds.size.y, ts)))
	return rects


## Godot NavigationMesh (vertices + clockwise-from-above polygons) for runtime use.
func to_navigation_mesh(tile: Dictionary) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	var polys: Array = tile.get("polygons", [])
	var hts: Array = tile.get("heights", [])
	var verts := PackedVector3Array()
	var lookup: Dictionary = {}
	var index_sets: Array[PackedInt32Array] = []
	for pi in polys.size():
		var poly: PackedVector2Array = polys[pi]
		var hs := PackedFloat32Array()
		if pi < hts.size():
			hs = hts[pi]
		var idxs := PackedInt32Array()
		for k in poly.size():
			var y: float = hs[k] if k < hs.size() else 0.0
			var key := Vector3i(roundi(poly[k].x * 1000.0), roundi(y * 1000.0), roundi(poly[k].y * 1000.0))
			if not lookup.has(key):
				lookup[key] = verts.size()
				verts.append(Vector3(poly[k].x, y, poly[k].y))
			idxs.append(int(lookup[key]))
		index_sets.append(idxs)
	mesh.vertices = verts
	for idxs in index_sets:
		mesh.add_polygon(idxs)
	return mesh


func _tile_task(job: int, index: int, triangles: PackedVector3Array, rect: AABB) -> void:
	var r: Dictionary = bake_tile(triangles, rect)
	_mutex.lock()
	var state: Dictionary = _jobs[job]
	(state["results"] as Array)[index] = r
	_mutex.unlock()


# ------------------------------------------------------------- voxelization

func _min_y(tris: PackedVector3Array, x0: float, z0: float, x1: float, z1: float) -> float:
	var lowest: float = INF
	for i in tris.size():
		var p: Vector3 = tris[i]
		if p.x >= x0 - 1.0 and p.x <= x1 + 1.0 and p.z >= z0 - 1.0 and p.z <= z1 + 1.0:
			lowest = minf(lowest, p.y)
	return 0.0 if lowest == INF else lowest


static func _clip(poly: PackedVector3Array, axis: int, v: float, keep_ge: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cnt: int = poly.size()
	var sgn: float = 1.0 if keep_ge else -1.0
	for i in cnt:
		var p: Vector3 = poly[i]
		var q: Vector3 = poly[(i + 1) % cnt]
		var dp: float = (p[axis] - v) * sgn
		var dq: float = (q[axis] - v) * sgn
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			var ip: Vector3 = p.lerp(q, dp / (dp - dq))
			ip[axis] = v
			out.append(ip)
	return out


func _rasterize(ctx: Ctx, tris: PackedVector3Array) -> void:
	var tri_count: int = int(tris.size() / 3.0)
	for t in tri_count:
		var a: Vector3 = tris[t * 3]
		var b: Vector3 = tris[t * 3 + 1]
		var c: Vector3 = tris[t * 3 + 2]
		var nrm: Vector3 = (b - a).cross(c - a)
		var nl: float = nrm.length()
		if nl < 1e-9:
			continue
		var walk: int = 1 if nrm.y / nl > ctx.slope_cos else 0
		var mn: Vector3 = a.min(b).min(c)
		var mx: Vector3 = a.max(b).max(c)
		var gx0: int = floori((mn.x - ctx.bmin.x) / ctx.cs)
		var gx1: int = maxi(gx0, floori((mx.x - ctx.bmin.x) / ctx.cs - 0.0001))
		var gz0: int = floori((mn.z - ctx.bmin.z) / ctx.cs)
		var gz1: int = maxi(gz0, floori((mx.z - ctx.bmin.z) / ctx.cs - 0.0001))
		if gx1 < 0 or gz1 < 0 or gx0 >= ctx.gw or gz0 >= ctx.gh:
			continue
		gx0 = maxi(gx0, 0)
		gz0 = maxi(gz0, 0)
		gx1 = mini(gx1, ctx.gw - 1)
		gz1 = mini(gz1, ctx.gh - 1)
		var poly := PackedVector3Array([a, b, c])
		for gz in range(gz0, gz1 + 1):
			var row: PackedVector3Array = _clip(poly, 2, ctx.bmin.z + gz * ctx.cs, true)
			row = _clip(row, 2, ctx.bmin.z + (gz + 1) * ctx.cs, false)
			if row.size() < 3:
				continue
			for gx in range(gx0, gx1 + 1):
				var cell: PackedVector3Array = _clip(row, 0, ctx.bmin.x + gx * ctx.cs, true)
				cell = _clip(cell, 0, ctx.bmin.x + (gx + 1) * ctx.cs, false)
				if cell.size() < 3:
					continue
				var ylo: float = INF
				var yhi: float = -INF
				for k in cell.size():
					ylo = minf(ylo, cell[k].y)
					yhi = maxf(yhi, cell[k].y)
				var smin: int = floori((ylo - ctx.bmin.y) / ctx.ch)
				var smax: int = ceili((yhi - ctx.bmin.y) / ctx.ch)
				if smax < 0:
					continue
				smin = maxi(smin, 0)
				smax = maxi(smax, smin + 1)
				_add_span(ctx, gz * ctx.gw + gx, smin, smax, walk)


## Inserts a span into its column, merging overlaps. The merged area comes from
## the span with the higher top; within climb height of each other the walkable
## flag wins (Recast's flag-merge threshold).
func _add_span(ctx: Ctx, col: int, smin: int, smax: int, area: int) -> void:
	var arr: PackedInt32Array = ctx.cols[col]
	var out := PackedInt32Array()
	var nmin: int = smin
	var nmax: int = smax
	var narea: int = area
	var inserted: bool = false
	var i: int = 0
	while i < arr.size():
		var cmin: int = arr[i]
		var cmax: int = arr[i + 1]
		var carea: int = arr[i + 2]
		if cmax < nmin:
			out.append_array(PackedInt32Array([cmin, cmax, carea]))
		elif cmin > nmax:
			if not inserted:
				out.append_array(PackedInt32Array([nmin, nmax, narea]))
				inserted = true
			out.append_array(PackedInt32Array([cmin, cmax, carea]))
		else:
			if absi(nmax - cmax) <= ctx.climb:
				narea = maxi(narea, carea)
			elif cmax > nmax:
				narea = carea
			nmin = mini(nmin, cmin)
			nmax = maxi(nmax, cmax)
		i += 3
	if not inserted:
		out.append_array(PackedInt32Array([nmin, nmax, narea]))
	ctx.cols[col] = out


# ---------------------------------------------------------------- filtering

static func _n3(arr: PackedInt32Array) -> int:
	@warning_ignore("integer_division")
	return arr.size() / 3


func _filter(ctx: Ctx) -> void:
	var total: int = ctx.gw * ctx.gh
	# low hanging obstacles
	for c in total:
		var arr: PackedInt32Array = ctx.cols[c]
		var prev_walk: bool = false
		var prev_top: int = 0
		var changed: bool = false
		for k in _n3(arr):
			var walk: bool = arr[k * 3 + 2] != 0
			if not walk and prev_walk and arr[k * 3 + 1] - prev_top <= ctx.climb:
				arr[k * 3 + 2] = 1
				changed = true
			prev_walk = walk
			prev_top = arr[k * 3 + 1]
		if changed:
			ctx.cols[c] = arr
	# ledge spans
	for z in ctx.gh:
		for x in ctx.gw:
			var c: int = z * ctx.gw + x
			var arr: PackedInt32Array = ctx.cols[c]
			var cnt: int = _n3(arr)
			var changed: bool = false
			for k in cnt:
				if arr[k * 3 + 2] == 0:
					continue
				var bot: int = arr[k * 3 + 1]
				var top: int = arr[(k + 1) * 3] if k + 1 < cnt else INF_H
				var minh: int = INF_H
				var asmin: int = bot
				var asmax: int = bot
				for d in 4:
					var nx: int = x + DIR_X[d]
					var nz: int = z + DIR_Z[d]
					if nx < 0 or nz < 0 or nx >= ctx.gw or nz >= ctx.gh:
						minh = mini(minh, -ctx.climb - 1)
						continue
					var narr: PackedInt32Array = ctx.cols[nz * ctx.gw + nx]
					var ncnt: int = _n3(narr)
					var nbot: int = -ctx.climb
					var ntop: int = narr[0] if ncnt > 0 else INF_H
					if mini(top, ntop) - maxi(bot, nbot) > ctx.walk_h:
						minh = mini(minh, nbot - bot)
					for m in ncnt:
						nbot = narr[m * 3 + 1]
						ntop = narr[(m + 1) * 3] if m + 1 < ncnt else INF_H
						if mini(top, ntop) - maxi(bot, nbot) > ctx.walk_h:
							minh = mini(minh, nbot - bot)
							if absi(nbot - bot) <= ctx.climb:
								asmin = mini(asmin, nbot)
								asmax = maxi(asmax, nbot)
				if minh < -ctx.climb or asmax - asmin > ctx.climb:
					arr[k * 3 + 2] = 0
					changed = true
			if changed:
				ctx.cols[c] = arr
	# low clearance
	for c in total:
		var arr: PackedInt32Array = ctx.cols[c]
		var cnt: int = _n3(arr)
		var changed: bool = false
		for k in cnt:
			var top: int = arr[(k + 1) * 3] if k + 1 < cnt else INF_H
			if arr[k * 3 + 2] != 0 and top - arr[k * 3 + 1] < ctx.walk_h:
				arr[k * 3 + 2] = 0
				changed = true
		if changed:
			ctx.cols[c] = arr


func _build_compact_from_cols(ctx: Ctx) -> void:
	var xs := PackedInt32Array()
	var zs := PackedInt32Array()
	var ys := PackedInt32Array()
	var hs := PackedInt32Array()
	for z in ctx.gh:
		for x in ctx.gw:
			var arr: PackedInt32Array = ctx.cols[z * ctx.gw + x]
			var cnt: int = _n3(arr)
			for k in cnt:
				if arr[k * 3 + 2] == 0:
					continue
				xs.append(x)
				zs.append(z)
				ys.append(arr[k * 3 + 1])
				hs.append((arr[(k + 1) * 3] if k + 1 < cnt else INF_H) - arr[k * 3 + 1])
	_set_compact(ctx, xs, zs, ys, hs)


## Installs span lists (sorted by column) and computes neighbour connections.
func _set_compact(ctx: Ctx, xs: PackedInt32Array, zs: PackedInt32Array, ys: PackedInt32Array, hs: PackedInt32Array) -> void:
	ctx.n = xs.size()
	ctx.sx = xs
	ctx.sz = zs
	ctx.sy = ys
	ctx.sh = hs
	ctx.col_start = PackedInt32Array()
	ctx.col_start.resize(ctx.gw * ctx.gh)
	ctx.col_count = PackedInt32Array()
	ctx.col_count.resize(ctx.gw * ctx.gh)
	for i in ctx.n:
		var c: int = zs[i] * ctx.gw + xs[i]
		if ctx.col_count[c] == 0:
			ctx.col_start[c] = i
		ctx.col_count[c] += 1
	ctx.con = PackedInt32Array()
	ctx.con.resize(ctx.n * 4)
	ctx.con.fill(-1)
	for i in ctx.n:
		for d in 4:
			var nx: int = xs[i] + DIR_X[d]
			var nz: int = zs[i] + DIR_Z[d]
			if nx < 0 or nz < 0 or nx >= ctx.gw or nz >= ctx.gh:
				continue
			var nc: int = nz * ctx.gw + nx
			for m in ctx.col_count[nc]:
				var j: int = ctx.col_start[nc] + m
				var bot: int = maxi(ys[i], ys[j])
				var top: int = mini(ys[i] + hs[i], ys[j] + hs[j])
				if top - bot >= ctx.walk_h and absi(ys[j] - ys[i]) <= ctx.climb:
					ctx.con[i * 4 + d] = j
					break


# ------------------------------------------------------------------ erosion

func _erode(ctx: Ctx) -> void:
	if ctx.radius <= 0 or ctx.n == 0:
		return
	var dist := PackedInt32Array()
	dist.resize(ctx.n)
	dist.fill(0xffff)
	for i in ctx.n:
		for d in 4:
			if ctx.con[i * 4 + d] < 0:
				dist[i] = 0
	for i in ctx.n:
		var c0: int = ctx.con[i * 4]
		if c0 >= 0:
			dist[i] = mini(dist[i], dist[c0] + 2)
			var c03: int = ctx.con[c0 * 4 + 3]
			if c03 >= 0:
				dist[i] = mini(dist[i], dist[c03] + 3)
		var c3: int = ctx.con[i * 4 + 3]
		if c3 >= 0:
			dist[i] = mini(dist[i], dist[c3] + 2)
			var c32: int = ctx.con[c3 * 4 + 2]
			if c32 >= 0:
				dist[i] = mini(dist[i], dist[c32] + 3)
	for i in range(ctx.n - 1, -1, -1):
		var c2: int = ctx.con[i * 4 + 2]
		if c2 >= 0:
			dist[i] = mini(dist[i], dist[c2] + 2)
			var c21: int = ctx.con[c2 * 4 + 1]
			if c21 >= 0:
				dist[i] = mini(dist[i], dist[c21] + 3)
		var c1: int = ctx.con[i * 4 + 1]
		if c1 >= 0:
			dist[i] = mini(dist[i], dist[c1] + 2)
			var c10: int = ctx.con[c1 * 4]
			if c10 >= 0:
				dist[i] = mini(dist[i], dist[c10] + 3)
	var thr: int = ctx.radius * 2
	var xs := PackedInt32Array()
	var zs := PackedInt32Array()
	var ys := PackedInt32Array()
	var hs := PackedInt32Array()
	for i in ctx.n:
		if dist[i] >= thr:
			xs.append(ctx.sx[i])
			zs.append(ctx.sz[i])
			ys.append(ctx.sy[i])
			hs.append(ctx.sh[i])
	_set_compact(ctx, xs, zs, ys, hs)


# ------------------------------------------------------------------ regions

## Monotone partitioning: sweep rows, each run joins the region above it only
## when that is a one-to-one link, which keeps every region hole free.
func _build_regions(ctx: Ctx, min_area: int) -> void:
	ctx.reg = PackedInt32Array()
	ctx.reg.resize(ctx.n)
	var next_id: int = 1
	for z in ctx.gh:
		var sw_nei := PackedInt32Array([0])
		var sw_ns := PackedInt32Array([0])
		var prev := PackedInt32Array()
		prev.resize(next_id + 1)
		var row_spans: Array[int] = []
		for x in ctx.gw:
			var c: int = z * ctx.gw + x
			for k in ctx.col_count[c]:
				var i: int = ctx.col_start[c] + k
				var sid: int = 0
				var c0: int = ctx.con[i * 4]
				if c0 >= 0 and ctx.reg[c0] != 0:
					sid = ctx.reg[c0]
				if sid == 0:
					sid = sw_nei.size()
					sw_nei.append(0)
					sw_ns.append(0)
				var c3: int = ctx.con[i * 4 + 3]
				if c3 >= 0 and ctx.reg[c3] != 0:
					var nr: int = ctx.reg[c3]
					if sw_nei[sid] == 0 or sw_nei[sid] == nr:
						sw_nei[sid] = nr
						sw_ns[sid] += 1
						prev[nr] += 1
					else:
						sw_nei[sid] = -1
				ctx.reg[i] = sid
				row_spans.append(i)
		var sw_id := PackedInt32Array()
		sw_id.resize(sw_nei.size())
		for s in range(1, sw_nei.size()):
			if sw_nei[s] > 0 and prev[sw_nei[s]] == sw_ns[s]:
				sw_id[s] = sw_nei[s]
			else:
				sw_id[s] = next_id
				next_id += 1
		for i in row_spans:
			ctx.reg[i] = sw_id[ctx.reg[i]]
	# drop tiny isolated regions
	var counts := PackedInt32Array()
	counts.resize(next_id)
	var linked := PackedInt32Array()
	linked.resize(next_id)
	for i in ctx.n:
		var r: int = ctx.reg[i]
		counts[r] += 1
		for d in 4:
			var nb: int = ctx.con[i * 4 + d]
			if nb >= 0 and ctx.reg[nb] != r:
				linked[r] = 1
	for i in ctx.n:
		var r2: int = ctx.reg[i]
		if counts[r2] < min_area and linked[r2] == 0:
			ctx.reg[i] = 0


# ------------------------------------------------------- contours / polygons

func _corner_h(ctx: Ctx, i: int, dir: int) -> int:
	var hgt: int = ctx.sy[i]
	var dirp: int = (dir + 1) & 3
	var a: int = ctx.con[i * 4 + dir]
	if a >= 0:
		hgt = maxi(hgt, ctx.sy[a])
		var b: int = ctx.con[a * 4 + dirp]
		if b >= 0:
			hgt = maxi(hgt, ctx.sy[b])
	var a2: int = ctx.con[i * 4 + dirp]
	if a2 >= 0:
		hgt = maxi(hgt, ctx.sy[a2])
		var b2: int = ctx.con[a2 * 4 + dir]
		if b2 >= 0:
			hgt = maxi(hgt, ctx.sy[b2])
	return hgt


func _walk_contour(ctx: Ctx, start: int, flags: PackedInt32Array) -> Array[Vector4i]:
	var pts: Array[Vector4i] = []
	var i: int = start
	var dir: int = 0
	while (flags[i] & (1 << dir)) == 0:
		dir += 1
	var start_dir: int = dir
	var iter: int = 0
	while iter < 40000:
		iter += 1
		if (flags[i] & (1 << dir)) != 0:
			var px: int = ctx.sx[i]
			var pz: int = ctx.sz[i]
			var py: int = _corner_h(ctx, i, dir)
			match dir:
				0:
					pz += 1
				1:
					px += 1
					pz += 1
				2:
					px += 1
			var r: int = 0
			var nb: int = ctx.con[i * 4 + dir]
			if nb >= 0:
				r = ctx.reg[nb]
			pts.append(Vector4i(px, py, pz, r))
			flags[i] = flags[i] & ~(1 << dir)
			dir = (dir + 1) & 3
		else:
			var ni: int = ctx.con[i * 4 + dir]
			if ni < 0:
				break
			i = ni
			dir = (dir + 3) & 3
		if i == start and dir == start_dir:
			break
	return pts


static func _dist_sq_seg(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var dx: float = bx - ax
	var dz: float = bz - az
	var d: float = dx * dx + dz * dz
	var t: float = (px - ax) * dx + (pz - az) * dz
	if d > 0.0:
		t = clampf(t / d, 0.0, 1.0)
	else:
		t = 0.0
	var ex: float = ax + t * dx - px
	var ez: float = az + t * dz - pz
	return ex * ex + ez * ez


## Douglas-Peucker on wall edges only; region-to-region edges keep just the
## vertices where the neighbour changes so adjacent regions share vertices.
func _simplify(raw: Array[Vector4i], max_err: float) -> Array[Vector4i]:
	var n: int = raw.size()
	var simp: Array[Vector4i] = []
	var has_conn: bool = false
	for i in n:
		if raw[i].w != 0:
			has_conn = true
			break
	if has_conn:
		for i in n:
			if raw[i].w != raw[(i + 1) % n].w:
				simp.append(Vector4i(raw[i].x, raw[i].y, raw[i].z, i))
	if simp.is_empty():
		var ll: int = 0
		var ur: int = 0
		for i in n:
			if raw[i].x < raw[ll].x or (raw[i].x == raw[ll].x and raw[i].z < raw[ll].z):
				ll = i
			if raw[i].x > raw[ur].x or (raw[i].x == raw[ur].x and raw[i].z > raw[ur].z):
				ur = i
		simp.append(Vector4i(raw[ll].x, raw[ll].y, raw[ll].z, ll))
		if ur != ll:
			simp.append(Vector4i(raw[ur].x, raw[ur].y, raw[ur].z, ur))
	var err_sq: float = max_err * max_err
	var s: int = 0
	while s < simp.size():
		var ii: int = (s + 1) % simp.size()
		var ax: int = simp[s].x
		var az: int = simp[s].z
		var ai: int = simp[s].w
		var bx: int = simp[ii].x
		var bz: int = simp[ii].z
		var bi: int = simp[ii].w
		var maxd: float = 0.0
		var maxi_: int = -1
		var ci: int
		var cinc: int
		var endi: int
		if bx > ax or (bx == ax and bz > az):
			cinc = 1
			ci = (ai + 1) % n
			endi = bi
		else:
			cinc = n - 1
			ci = (bi + cinc) % n
			endi = ai
			var tx: int = ax
			ax = bx
			bx = tx
			var tz: int = az
			az = bz
			bz = tz
		if raw[ci].w == 0:
			while ci != endi:
				var d: float = _dist_sq_seg(raw[ci].x, raw[ci].z, ax, az, bx, bz)
				if d > maxd:
					maxd = d
					maxi_ = ci
				ci = (ci + cinc) % n
		if maxi_ != -1 and maxd > err_sq:
			simp.insert(s + 1, Vector4i(raw[maxi_].x, raw[maxi_].y, raw[maxi_].z, maxi_))
		else:
			s += 1
	# remove consecutive duplicates
	var clean: Array[Vector4i] = []
	for v in simp:
		if clean.is_empty() or clean[clean.size() - 1].x != v.x or clean[clean.size() - 1].z != v.z:
			clean.append(v)
	while clean.size() > 1 and clean[0].x == clean[clean.size() - 1].x and clean[0].z == clean[clean.size() - 1].z:
		clean.pop_back()
	return clean


## Returns Array[PackedVector3Array] of world-space convex polygons (x, y, z).
func _build_polys(ctx: Ctx, nvp: int, max_err: float) -> Array:
	var flags := PackedInt32Array()
	flags.resize(ctx.n)
	for i in ctx.n:
		if ctx.reg[i] == 0:
			continue
		var res: int = 0
		for d in 4:
			var nb: int = ctx.con[i * 4 + d]
			if nb >= 0 and ctx.reg[nb] == ctx.reg[i]:
				res |= 1 << d
		flags[i] = res ^ 0xf
	var best_area: Dictionary = {}
	var best_pts: Dictionary = {}
	for i in ctx.n:
		if ctx.reg[i] == 0 or flags[i] == 0:
			continue
		var raw: Array[Vector4i] = _walk_contour(ctx, i, flags)
		if raw.size() < 3:
			continue
		var simp: Array[Vector4i] = _simplify(raw, max_err)
		if simp.size() < 3:
			continue
		var p2 := PackedVector2Array()
		for v in simp:
			p2.append(Vector2(v.x, v.z))
		var area: float = _signed_area(p2)
		if absf(area) < 1e-6:
			continue
		if area < 0.0:
			simp.reverse()
			area = -area
		var rid: int = ctx.reg[i]
		if not best_area.has(rid) or float(best_area[rid]) < area:
			best_area[rid] = area
			best_pts[rid] = simp
	var out: Array = []
	for rid in best_pts:
		var pts: Array[Vector4i] = best_pts[rid]
		var p2 := PackedVector2Array()
		for v in pts:
			p2.append(Vector2(v.x, v.z))
		var polys: Array[PackedInt32Array] = _merge_polys(_triangulate(p2), p2, nvp)
		for poly in polys:
			var world := PackedVector3Array()
			for idx in poly:
				var v: Vector4i = pts[idx]
				world.append(Vector3(ctx.bmin.x + v.x * ctx.cs, ctx.bmin.y + v.y * ctx.ch, ctx.bmin.z + v.z * ctx.cs))
			out.append(world)
	return out


static func _signed_area(p: PackedVector2Array) -> float:
	var a: float = 0.0
	var cnt: int = p.size()
	for i in cnt:
		var q: Vector2 = p[(i + 1) % cnt]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


## Ear clipping of a positively oriented simple polygon.
static func _triangulate(pts: PackedVector2Array) -> Array[PackedInt32Array]:
	var tris: Array[PackedInt32Array] = []
	var idx: Array[int] = []
	for i in pts.size():
		idx.append(i)
	var guard: int = 0
	while idx.size() > 3 and guard < 100000:
		guard += 1
		var m: int = idx.size()
		var clipped: bool = false
		for k in m:
			var i0: int = idx[(k + m - 1) % m]
			var i1: int = idx[k]
			var i2: int = idx[(k + 1) % m]
			var p0: Vector2 = pts[i0]
			var p1: Vector2 = pts[i1]
			var p2: Vector2 = pts[i2]
			if _cross2(p0, p1, p2) <= 0.0:
				continue
			var ok: bool = true
			for j in idx:
				if j == i0 or j == i1 or j == i2:
					continue
				var pj: Vector2 = pts[j]
				if pj == p0 or pj == p1 or pj == p2:
					continue
				if _cross2(p0, p1, pj) >= 0.0 and _cross2(p1, p2, pj) >= 0.0 and _cross2(p2, p0, pj) >= 0.0:
					ok = false
					break
			if ok:
				tris.append(PackedInt32Array([i0, i1, i2]))
				idx.remove_at(k)
				clipped = true
				break
		if not clipped:
			# degenerate input: drop the flattest vertex
			var m2: int = idx.size()
			var best_k: int = 0
			var best_c: float = INF
			for k in m2:
				var c: float = absf(_cross2(pts[idx[(k + m2 - 1) % m2]], pts[idx[k]], pts[idx[(k + 1) % m2]]))
				if c < best_c:
					best_c = c
					best_k = k
			idx.remove_at(best_k)
	if idx.size() == 3 and _cross2(pts[idx[0]], pts[idx[1]], pts[idx[2]]) > 0.0:
		tris.append(PackedInt32Array([idx[0], idx[1], idx[2]]))
	return tris


static func _is_convex(poly: PackedInt32Array, pts: PackedVector2Array) -> bool:
	var cnt: int = poly.size()
	for i in cnt:
		if _cross2(pts[poly[(i + cnt - 1) % cnt]], pts[poly[i]], pts[poly[(i + 1) % cnt]]) < 0.0:
			return false
	return true


## Greedily merges polygons across their longest shared edge while the result
## stays convex and has at most nvp vertices (Recast's mergePolyVerts).
static func _merge_polys(input: Array[PackedInt32Array], pts: PackedVector2Array, nvp: int) -> Array[PackedInt32Array]:
	var polys: Array[PackedInt32Array] = input.duplicate()
	while polys.size() > 1:
		var best_len: float = -1.0
		var best_a: int = -1
		var best_b: int = -1
		var best_poly := PackedInt32Array()
		for a in polys.size():
			var pa: PackedInt32Array = polys[a]
			for b in range(a + 1, polys.size()):
				var pb: PackedInt32Array = polys[b]
				if pa.size() + pb.size() - 2 > nvp:
					continue
				for ea in pa.size():
					var va0: int = pa[ea]
					var va1: int = pa[(ea + 1) % pa.size()]
					for eb in pb.size():
						if pb[eb] != va1 or pb[(eb + 1) % pb.size()] != va0:
							continue
						var merged := PackedInt32Array()
						for q in pa.size() - 1:
							merged.append(pa[(ea + 1 + q) % pa.size()])
						for q in pb.size() - 1:
							merged.append(pb[(eb + 1 + q) % pb.size()])
						if not _is_convex(merged, pts):
							continue
						var len_sq: float = pts[va0].distance_squared_to(pts[va1])
						if len_sq > best_len:
							best_len = len_sq
							best_a = a
							best_b = b
							best_poly = merged
		if best_a < 0:
			break
		polys[best_a] = best_poly
		polys.remove_at(best_b)
	return polys


# --------------------------------------------------------------- tile clipping

func _clip_to_rect(poly: PackedVector3Array, rect: Rect2) -> PackedVector3Array:
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var z0: float = rect.position.y
	var z1: float = rect.end.y
	var snapped_poly := PackedVector3Array()
	for k in poly.size():
		var p: Vector3 = poly[k]
		for bound in [x0, x1]:
			if absf(p.x - float(bound)) < 1e-4:
				p.x = float(bound)
		for bound in [z0, z1]:
			if absf(p.z - float(bound)) < 1e-4:
				p.z = float(bound)
		snapped_poly.append(p)
	var out: PackedVector3Array = _clip(snapped_poly, 0, x0, true)
	out = _clip(out, 0, x1, false)
	out = _clip(out, 2, z0, true)
	out = _clip(out, 2, z1, false)
	var clean := PackedVector3Array()
	for k in out.size():
		if clean.is_empty() or absf(clean[clean.size() - 1].x - out[k].x) > 1e-5 or absf(clean[clean.size() - 1].z - out[k].z) > 1e-5:
			clean.append(out[k])
	while clean.size() > 1 and absf(clean[0].x - clean[clean.size() - 1].x) <= 1e-5 and absf(clean[0].z - clean[clean.size() - 1].z) <= 1e-5:
		clean.remove_at(clean.size() - 1)
	return clean
