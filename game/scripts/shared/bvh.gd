extends RefCounted
## CPU bounding volume hierarchy over a triangle soup (binned SAH build, flat node arrays,
## Moller-Trumbore ray/triangle test). Used by the path tracer for light baking.
##
## Ported from concepts and public write-ups; no third-party source text was copied:
##  - Jacco Bikker, "How to build a BVH" series (binned SAH build, flat node layout, stackless-free
##    stack traversal), https://jacco.ompf2.com/2022/04/13/how-to-build-a-bvh-part-1-basics/
##    (article code is public domain / ZLIB-style permissive; algorithm re-implemented here).
##  - Tomas Moller and Ben Trumbore, "Fast, Minimum Storage Ray/Triangle Intersection", 1997
##    (published algorithm, J. Graphics Tools 2(1)).
##  - Peter Shirley, "Ray Tracing in One Weekend" series (CC0), slab AABB test:
##    https://raytracing.github.io/
##  - Pharr/Jakob/Humphreys, "Physically Based Rendering" (BSD-2 code, pbrt-v3/v4), SAH bucket
##    cost model: https://github.com/mmp/pbrt-v4
## No Apache-2.0, GPL or LGPL code is included.

const BINS := 16
const MAX_LEAF := 2          ## SAH may stop at or below this many triangles
const FORCE_SPLIT := 8       ## leaves are never larger than this
const T_MIN := 0.00001
const MISS := 1.0e30

## Node i: bounds node_min/node_max. Leaf when node_cnt[i] > 0 (node_first[i] is the first slot in
## the leaf-ordered triangle arrays). Interior: node_first[i] is the left child, right = left + 1.
var node_min := PackedVector3Array()
var node_max := PackedVector3Array()
var node_first := PackedInt32Array()
var node_cnt := PackedInt32Array()
## Leaf-ordered triangle data (v0, v1 - v0, v2 - v0) and map back to the input triangle index.
var tri_v0 := PackedVector3Array()
var tri_e1 := PackedVector3Array()
var tri_e2 := PackedVector3Array()
var tri_index := PackedInt32Array()

var tri_count: int = 0
var _leaf_count: int = 0
var _max_depth: int = 0
var _build_ms: float = 0.0
var _stack := PackedInt32Array()


## Builds the hierarchy; `tris` holds three vertices per triangle.
func build(tris: PackedVector3Array) -> void:
	var t0 := Time.get_ticks_usec()
	node_min.clear()
	node_max.clear()
	node_first.clear()
	node_cnt.clear()
	tri_v0.clear()
	tri_e1.clear()
	tri_e2.clear()
	tri_index.clear()
	_leaf_count = 0
	_max_depth = 0
	@warning_ignore("integer_division")
	tri_count = tris.size() / 3
	if tri_count == 0:
		return
	_build_tris = tris
	var tb_min := PackedVector3Array()
	var tb_max := PackedVector3Array()
	var cen := PackedVector3Array()
	tb_min.resize(tri_count)
	tb_max.resize(tri_count)
	cen.resize(tri_count)
	tri_index.resize(tri_count)
	for i in tri_count:
		var a := tris[i * 3]
		var b := tris[i * 3 + 1]
		var c := tris[i * 3 + 2]
		tb_min[i] = a.min(b).min(c)
		tb_max[i] = a.max(b).max(c)
		cen[i] = (tb_min[i] + tb_max[i]) * 0.5
		tri_index[i] = i
	_push_node()
	var jobs: Array[Vector4i] = [Vector4i(0, 0, tri_count, 0)]
	while not jobs.is_empty():
		var job: Vector4i = jobs.pop_back()
		var node := job.x
		var start := job.y
		var cnt := job.z
		var depth := job.w
		_max_depth = maxi(_max_depth, depth)
		var lo := Vector3(MISS, MISS, MISS)
		var hi := Vector3(-MISS, -MISS, -MISS)
		var clo := lo
		var chi := hi
		for i in range(start, start + cnt):
			var ti := tri_index[i]
			lo = lo.min(tb_min[ti])
			hi = hi.max(tb_max[ti])
			clo = clo.min(cen[ti])
			chi = chi.max(cen[ti])
		node_min[node] = lo
		node_max[node] = hi
		if cnt <= MAX_LEAF:
			_make_leaf(node, start, cnt)
			continue
		var split := _find_split(start, cnt, lo, hi, clo, chi, cen)
		var axis: int = split.x
		var best_bin: int = split.y
		var make_leaf: bool = split.z == 0 and cnt <= FORCE_SPLIT
		if make_leaf:
			_make_leaf(node, start, cnt)
			continue
		var mid := start + (cnt >> 1)
		if axis >= 0:
			var ext := chi - clo
			var scale := float(BINS) / ext[axis]
			var i := start
			var j := start + cnt - 1
			while i <= j:
				var b := mini(BINS - 1, int((cen[tri_index[i]][axis] - clo[axis]) * scale))
				if b <= best_bin:
					i += 1
				else:
					var tmp := tri_index[i]
					tri_index[i] = tri_index[j]
					tri_index[j] = tmp
					j -= 1
			if i > start and i < start + cnt:
				mid = i
		var left := node_min.size()
		_push_node()
		_push_node()
		node_first[node] = left
		node_cnt[node] = 0
		jobs.push_back(Vector4i(left, start, mid - start, depth + 1))
		jobs.push_back(Vector4i(left + 1, mid, start + cnt - mid, depth + 1))
	tri_v0.resize(tri_count)
	tri_e1.resize(tri_count)
	tri_e2.resize(tri_count)
	for k in tri_count:
		var ti := tri_index[k]
		var v0 := tris[ti * 3]
		tri_v0[k] = v0
		tri_e1[k] = tris[ti * 3 + 1] - v0
		tri_e2[k] = tris[ti * 3 + 2] - v0
	_stack.resize(_max_depth * 2 + 8)
	_build_tris = PackedVector3Array()
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _push_node() -> void:
	node_min.push_back(Vector3.ZERO)
	node_max.push_back(Vector3.ZERO)
	node_first.push_back(0)
	node_cnt.push_back(0)


func _make_leaf(node: int, start: int, cnt: int) -> void:
	node_first[node] = start
	node_cnt[node] = cnt
	_leaf_count += 1


static func _area(e: Vector3) -> float:
	return maxf(e.x, 0.0) * maxf(e.y, 0.0) + maxf(e.y, 0.0) * maxf(e.z, 0.0) + maxf(e.z, 0.0) * maxf(e.x, 0.0)


## Returns Vector3i(axis, bin, beats_leaf_cost). axis -1 means no usable axis.
func _find_split(start: int, cnt: int, lo: Vector3, hi: Vector3, clo: Vector3, chi: Vector3, cen: PackedVector3Array) -> Vector3i:
	var leaf_cost := float(cnt) * _area(hi - lo)
	var best_cost := MISS
	var best_axis := -1
	var best_bin := 0
	var ext := chi - clo
	for axis in 3:
		if ext[axis] < 0.000000001:
			continue
		var scale := float(BINS) / ext[axis]
		var bcount := PackedInt32Array()
		var bmin := PackedVector3Array()
		var bmax := PackedVector3Array()
		bcount.resize(BINS)
		bmin.resize(BINS)
		bmax.resize(BINS)
		for b in BINS:
			bmin[b] = Vector3(MISS, MISS, MISS)
			bmax[b] = Vector3(-MISS, -MISS, -MISS)
		for i in range(start, start + cnt):
			var ti := tri_index[i]
			var b := mini(BINS - 1, int((cen[ti][axis] - clo[axis]) * scale))
			bcount[b] += 1
			bmin[b] = bmin[b].min(_tb_lo(ti))
			bmax[b] = bmax[b].max(_tb_hi(ti))
		var left_area := PackedFloat32Array()
		var left_cnt := PackedInt32Array()
		left_area.resize(BINS - 1)
		left_cnt.resize(BINS - 1)
		var run_lo := Vector3(MISS, MISS, MISS)
		var run_hi := Vector3(-MISS, -MISS, -MISS)
		var run_n := 0
		for b in BINS - 1:
			run_n += bcount[b]
			run_lo = run_lo.min(bmin[b])
			run_hi = run_hi.max(bmax[b])
			left_cnt[b] = run_n
			left_area[b] = _area(run_hi - run_lo) if run_n > 0 else 0.0
		run_lo = Vector3(MISS, MISS, MISS)
		run_hi = Vector3(-MISS, -MISS, -MISS)
		run_n = 0
		for b in range(BINS - 1, 0, -1):
			run_n += bcount[b]
			run_lo = run_lo.min(bmin[b])
			run_hi = run_hi.max(bmax[b])
			var ln := left_cnt[b - 1]
			if ln == 0 or run_n == 0:
				continue
			var cost := float(ln) * left_area[b - 1] + float(run_n) * _area(run_hi - run_lo)
			if cost < best_cost:
				best_cost = cost
				best_axis = axis
				best_bin = b - 1
	return Vector3i(best_axis, best_bin, 1 if best_cost < leaf_cost else 0)


# Triangle bounds are recomputed from the build-time arrays held in _build_tris (set in build()).
var _build_tris := PackedVector3Array()


func _tb_lo(ti: int) -> Vector3:
	return _build_tris[ti * 3].min(_build_tris[ti * 3 + 1]).min(_build_tris[ti * 3 + 2])


func _tb_hi(ti: int) -> Vector3:
	return _build_tris[ti * 3].max(_build_tris[ti * 3 + 1]).max(_build_tris[ti * 3 + 2])


## Slab test. Returns entry distance (clamped to 0) or MISS.
func _box_t(i: int, o: Vector3, inv: Vector3, t_max: float) -> float:
	var lo := node_min[i]
	var hi := node_max[i]
	var t1 := (lo.x - o.x) * inv.x
	var t2 := (hi.x - o.x) * inv.x
	var tn := minf(t1, t2)
	var tf := maxf(t1, t2)
	t1 = (lo.y - o.y) * inv.y
	t2 = (hi.y - o.y) * inv.y
	tn = maxf(tn, minf(t1, t2))
	tf = minf(tf, maxf(t1, t2))
	t1 = (lo.z - o.z) * inv.z
	t2 = (hi.z - o.z) * inv.z
	tn = maxf(tn, minf(t1, t2))
	tf = minf(tf, maxf(t1, t2))
	if tf < maxf(tn, 0.0) or tn > t_max:
		return MISS
	return maxf(tn, 0.0)


static func _safe_inv(d: Vector3) -> Vector3:
	var x := d.x if absf(d.x) > 0.000000001 else 0.000000001
	var y := d.y if absf(d.y) > 0.000000001 else 0.000000001
	var z := d.z if absf(d.z) > 0.000000001 else 0.000000001
	return Vector3(1.0 / x, 1.0 / y, 1.0 / z)


## Closest hit along origin + t * dir for t in (0, t_max]. `normal` is geometric and faces the ray.
func intersect(origin: Vector3, dir: Vector3, t_max: float = 1.0e20) -> Dictionary:
	var best_t := t_max
	var best_k := -1
	var best_u := 0.0
	var best_v := 0.0
	if not node_cnt.is_empty() and _box_t(0, origin, _safe_inv(dir), best_t) < MISS:
		var inv := _safe_inv(dir)
		var sp := 0
		_stack[0] = 0
		sp = 1
		while sp > 0:
			sp -= 1
			var node := _stack[sp]
			var cnt := node_cnt[node]
			if cnt > 0:
				var first := node_first[node]
				for k in range(first, first + cnt):
					var e1 := tri_e1[k]
					var e2 := tri_e2[k]
					var pv := dir.cross(e2)
					var det := e1.dot(pv)
					if absf(det) < 0.000000000001:
						continue
					var inv_det := 1.0 / det
					var tv := origin - tri_v0[k]
					var u := tv.dot(pv) * inv_det
					if u < 0.0 or u > 1.0:
						continue
					var qv := tv.cross(e1)
					var v := dir.dot(qv) * inv_det
					if v < 0.0 or u + v > 1.0:
						continue
					var t := e2.dot(qv) * inv_det
					if t > T_MIN and t < best_t:
						best_t = t
						best_k = k
						best_u = u
						best_v = v
			else:
				var l := node_first[node]
				var tl := _box_t(l, origin, inv, best_t)
				var tr := _box_t(l + 1, origin, inv, best_t)
				if tl < MISS and tr < MISS:
					if tl <= tr:
						_stack[sp] = l + 1
						_stack[sp + 1] = l
					else:
						_stack[sp] = l
						_stack[sp + 1] = l + 1
					sp += 2
				elif tl < MISS:
					_stack[sp] = l
					sp += 1
				elif tr < MISS:
					_stack[sp] = l + 1
					sp += 1
	if best_k < 0:
		return {"hit": false, "t": t_max, "tri": -1, "u": 0.0, "v": 0.0, "normal": Vector3.ZERO}
	var n := tri_e1[best_k].cross(tri_e2[best_k]).normalized()
	if n.dot(dir) > 0.0:
		n = -n
	return {"hit": true, "t": best_t, "tri": tri_index[best_k], "u": best_u, "v": best_v, "normal": n}


## Any-hit shadow query: true when something blocks origin + t * dir for t in (0, t_max).
func occluded(origin: Vector3, dir: Vector3, t_max: float = 1.0e20) -> bool:
	if node_cnt.is_empty():
		return false
	var inv := _safe_inv(dir)
	if _box_t(0, origin, inv, t_max) >= MISS:
		return false
	var sp := 1
	_stack[0] = 0
	while sp > 0:
		sp -= 1
		var node := _stack[sp]
		var cnt := node_cnt[node]
		if cnt > 0:
			var first := node_first[node]
			for k in range(first, first + cnt):
				var e2 := tri_e2[k]
				var e1 := tri_e1[k]
				var pv := dir.cross(e2)
				var det := e1.dot(pv)
				if absf(det) < 0.000000000001:
					continue
				var inv_det := 1.0 / det
				var tv := origin - tri_v0[k]
				var u := tv.dot(pv) * inv_det
				if u < 0.0 or u > 1.0:
					continue
				var qv := tv.cross(e1)
				var v := dir.dot(qv) * inv_det
				if v < 0.0 or u + v > 1.0:
					continue
				var t := e2.dot(qv) * inv_det
				if t > T_MIN and t < t_max:
					return true
		else:
			var l := node_first[node]
			if _box_t(l, origin, inv, t_max) < MISS:
				_stack[sp] = l
				sp += 1
			if _box_t(l + 1, origin, inv, t_max) < MISS:
				_stack[sp] = l + 1
				sp += 1
	return false


## Build statistics. sah_cost is the expected traversal cost relative to the root area.
func get_stats() -> Dictionary:
	var sah := 0.0
	var root_area := 1.0
	if not node_cnt.is_empty():
		root_area = maxf(_area(node_max[0] - node_min[0]), 0.000001)
		for i in node_cnt.size():
			var a := _area(node_max[i] - node_min[i])
			sah += a * (float(node_cnt[i]) if node_cnt[i] > 0 else 1.0)
	return {
		"triangles": tri_count,
		"nodes": node_cnt.size(),
		"leaves": _leaf_count,
		"max_depth": _max_depth,
		"avg_leaf_size": float(tri_count) / float(maxi(_leaf_count, 1)),
		"sah_cost": sah / root_area,
		"build_ms": _build_ms,
	}
