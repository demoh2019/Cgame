extends RefCounted
## Cluster DAG LOD hierarchy and screen-space-error cut selection (Nanite-style, CPU).
##
## Credits / sources (concepts re-implemented from scratch, no code copied):
##   - "A Deep Dive into Nanite Virtualized Geometry", Karis et al., SIGGRAPH 2021
##     (cluster groups, locked group borders, parent-error cut rule).
##   - meshoptimizer by Arseny Kapoulkine, MIT license (clusterization and quadric
##     edge-collapse simplification ideas, locked vertices).
##   - Garland & Heckbert, "Surface Simplification Using Quadric Error Metrics" (1997).
##   - Bevy virtual geometry write-up (MIT / Apache-2.0), background only.
##
## Vertices must be welded (shared by index) so neighbouring clusters share ids.
## Hierarchy dictionary: vertices, clusters (Array of Dictionary), levels, roots.
## Cluster: indices (global triangle list), vertex_ids, center/radius (geometry sphere),
## cone_axis/cone_cutoff, level, error + lod_center/lod_radius (own LOD sphere, shared by
## the whole group that produced it), parent_error/parent_center/parent_radius (INF for
## roots), children (cluster ids of the group this cluster was simplified from).

const Meshlets = preload("res://scripts/shared/meshlets.gd")
const GROUP_SIZE := 4


static func build_hierarchy(vertices: PackedVector3Array, indices: PackedInt32Array, levels: int = 4) -> Dictionary:
	var clusters: Array = []
	var cur := PackedInt32Array()
	var built: int = 1
	var base: Array = Meshlets.build_meshlets(vertices, indices)
	for i in base.size():
		var m: Dictionary = base[i]
		var sph := Vector4(0, 0, 0, 0)
		var mc: Vector3 = m["bounds_center"]
		sph = Vector4(mc.x, mc.y, mc.z, float(m["bounds_radius"]))
		cur.append(clusters.size())
		clusters.append(_make_cluster(m, 0, 0.0, sph))
	for lvl in range(1, levels):
		if cur.size() <= 1:
			break
		var next := PackedInt32Array()
		var groups: Array = _group(clusters, cur)
		for gi in groups.size():
			var group: PackedInt32Array = groups[gi]
			var tris := PackedInt32Array()
			var child_err: float = 0.0
			var sph := Vector4.ZERO
			for k in group.size():
				var c: Dictionary = clusters[group[k]]
				var ci: PackedInt32Array = c["indices"]
				tris.append_array(ci)
				child_err = maxf(child_err, float(c["error"]))
				var lc: Vector3 = c["lod_center"]
				var s := Vector4(lc.x, lc.y, lc.z, float(c["lod_radius"]))
				sph = s if k == 0 else _merge_spheres(sph, s)
			var sim: Dictionary = _simplify(vertices, tris, _half(tris.size()))
			var sim_idx: PackedInt32Array = sim["indices"]
			if sim_idx.is_empty():
				continue
			var group_err: float = child_err + float(sim["error"])
			var pc := Vector3(sph.x, sph.y, sph.z)
			for k in group.size():
				var c: Dictionary = clusters[group[k]]
				c["parent_error"] = group_err
				c["parent_center"] = pc
				c["parent_radius"] = sph.w
			var parts: Array = Meshlets.build_meshlets(vertices, sim_idx)
			for pi in parts.size():
				var pm: Dictionary = parts[pi]
				var nc: Dictionary = _make_cluster(pm, lvl, group_err, sph)
				nc["children"] = group
				next.append(clusters.size())
				clusters.append(nc)
		if next.is_empty():
			break
		cur = next
		built = lvl + 1
	var roots := PackedInt32Array()
	for i in clusters.size():
		var c: Dictionary = clusters[i]
		if is_inf(float(c["parent_error"])):
			roots.append(i)
	return {"vertices": vertices, "clusters": clusters, "levels": built, "roots": roots}


## Clusters whose own projected error <= error_pixels < parent's projected error.
## Own and parent LOD values are shared across a group, so the cut has no cracks/overlap.
static func select_cut(hierarchy: Dictionary, camera_pos: Vector3, fov_y: float, screen_height: float, error_pixels: float = 1.0) -> PackedInt32Array:
	var clusters: Array = hierarchy["clusters"]
	var scale: float = screen_height / (2.0 * tan(fov_y * 0.5))
	var cut := PackedInt32Array()
	for i in clusters.size():
		var c: Dictionary = clusters[i]
		var own: float = _projected(c["error"], c["lod_center"], c["lod_radius"], camera_pos, scale)
		if own > error_pixels:
			continue
		var par: float = _projected(c["parent_error"], c["parent_center"], c["parent_radius"], camera_pos, scale)
		if par > error_pixels:
			cut.append(i)
	return cut


@warning_ignore("integer_division")
static func triangle_count(hierarchy: Dictionary, cut: PackedInt32Array) -> int:
	var clusters: Array = hierarchy["clusters"]
	var total: int = 0
	for id in cut:
		var c: Dictionary = clusters[id]
		var ci: PackedInt32Array = c["indices"]
		total += ci.size() / 3
	return total


## Keep all source attributes, including UV seams, normals, colors, tangents,
## skin and custom channels; simplifying a cluster changes only its indices.
## This is the non-native fallback for a material-preserving CPU LOD cut.
static func build_cut_arrays(source_arrays: Array, hierarchy: Dictionary, cut: PackedInt32Array) -> Array:
	if source_arrays.size() != Mesh.ARRAY_MAX or not (source_arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
		return []
	if not hierarchy.has("vertices") or not hierarchy.has("clusters"):
		return []
	var vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty() or hierarchy["vertices"] != vertices or not (hierarchy["clusters"] is Array):
		return []
	var clusters: Array = hierarchy["clusters"]
	var out_indices := PackedInt32Array()
	var visited := {}
	for id in cut:
		if id < 0 or id >= clusters.size() or visited.has(id) or not (clusters[id] is Dictionary):
			return []
		visited[id] = true
		var cluster: Dictionary = clusters[id]
		if not cluster.has("indices") or not (cluster["indices"] is PackedInt32Array):
			return []
		var part: PackedInt32Array = cluster["indices"]
		if part.is_empty() or part.size() % 3 != 0:
			return []
		for index in part:
			if index < 0 or index >= vertices.size():
				return []
		out_indices.append_array(part)
	if out_indices.is_empty():
		return []
	var arrays: Array = source_arrays.duplicate()
	arrays[Mesh.ARRAY_INDEX] = out_indices
	return arrays


static func _projected(err: float, center: Vector3, radius: float, cam: Vector3, scale: float) -> float:
	if is_inf(err):
		return INF
	if err <= 0.0:
		return 0.0
	return err * scale / maxf(cam.distance_to(center) - radius, 1.0e-4)


@warning_ignore("integer_division")
static func _half(index_count: int) -> int:
	return index_count / 3 / 2


static func _make_cluster(m: Dictionary, level: int, err: float, lod: Vector4) -> Dictionary:
	var vids: PackedInt32Array = m["vertex_ids"]
	var loc: PackedInt32Array = m["indices"]
	var gi := PackedInt32Array()
	gi.resize(loc.size())
	for i in loc.size():
		gi[i] = vids[loc[i]]
	return {
		"indices": gi,
		"vertex_ids": vids,
		"center": m["bounds_center"],
		"radius": m["bounds_radius"],
		"cone_axis": m["cone_axis"],
		"cone_cutoff": m["cone_cutoff"],
		"level": level,
		"error": err,
		"lod_center": Vector3(lod.x, lod.y, lod.z),
		"lod_radius": lod.w,
		"parent_error": INF,
		"parent_center": Vector3.ZERO,
		"parent_radius": 0.0,
		"children": PackedInt32Array(),
	}


static func _merge_spheres(a: Vector4, b: Vector4) -> Vector4:
	var ca := Vector3(a.x, a.y, a.z)
	var cb := Vector3(b.x, b.y, b.z)
	var d: float = ca.distance_to(cb)
	if d + b.w <= a.w:
		return a
	if d + a.w <= b.w:
		return b
	var r: float = (d + a.w + b.w) * 0.5
	var c: Vector3 = ca + (cb - ca) * ((r - a.w) / d)
	return Vector4(c.x, c.y, c.z, r * 1.00001)


## Greedily groups up to GROUP_SIZE clusters that share the most vertices.
static func _group(clusters: Array, ids: PackedInt32Array) -> Array:
	var vmap: Dictionary = {}
	for id in ids:
		var c: Dictionary = clusters[id]
		var vids: PackedInt32Array = c["vertex_ids"]
		for v in vids:
			if vmap.has(v):
				var lst: PackedInt32Array = vmap[v]
				lst.append(id)
				vmap[v] = lst
			else:
				vmap[v] = PackedInt32Array([id])
	var assigned: Dictionary = {}
	var groups: Array = []
	for seed_id in ids:
		if assigned.has(seed_id):
			continue
		var group := PackedInt32Array([seed_id])
		assigned[seed_id] = true
		var weights: Dictionary = {}
		var add_id: int = seed_id
		while true:
			var ac: Dictionary = clusters[add_id]
			var avids: PackedInt32Array = ac["vertex_ids"]
			for v in avids:
				var lst: PackedInt32Array = vmap[v]
				for o in lst:
					if not assigned.has(o):
						weights[o] = int(weights.get(o, 0)) + 1
			if group.size() >= GROUP_SIZE:
				break
			var best: int = -1
			var bw: int = 0
			for k in weights:
				var ko: int = k
				var w: int = weights[k]
				if not assigned.has(ko) and (w > bw or (w == bw and best >= 0 and ko < best)):
					best = ko
					bw = w
			if best < 0:
				break
			assigned[best] = true
			group.append(best)
			add_id = best
		groups.append(group)
	return groups


static func _edge_key(a: int, b: int) -> int:
	if a > b:
		return (b << 32) | a
	return (a << 32) | b


static func _add_plane(q: PackedFloat64Array, vi: int, nx: float, ny: float, nz: float, d: float) -> void:
	var b: int = vi * 10
	q[b] += nx * nx
	q[b + 1] += nx * ny
	q[b + 2] += nx * nz
	q[b + 3] += nx * d
	q[b + 4] += ny * ny
	q[b + 5] += ny * nz
	q[b + 6] += ny * d
	q[b + 7] += nz * nz
	q[b + 8] += nz * d
	q[b + 9] += d * d


static func _q_cost(q: PackedFloat64Array, ia: int, ib: int, p: Vector3) -> float:
	var a: int = ia * 10
	var b: int = ib * 10
	var x: float = p.x
	var y: float = p.y
	var z: float = p.z
	var r: float = (q[a] + q[b]) * x * x + 2.0 * (q[a + 1] + q[b + 1]) * x * y + 2.0 * (q[a + 2] + q[b + 2]) * x * z + 2.0 * (q[a + 3] + q[b + 3]) * x
	r += (q[a + 4] + q[b + 4]) * y * y + 2.0 * (q[a + 5] + q[b + 5]) * y * z + 2.0 * (q[a + 6] + q[b + 6]) * y
	r += (q[a + 7] + q[b + 7]) * z * z + 2.0 * (q[a + 8] + q[b + 8]) * z + (q[a + 9] + q[b + 9])
	return maxf(r, 0.0)


## Quadric edge-collapse of a triangle soup toward target_tris. Vertices on the soup's
## boundary edges are locked (never moved or removed), so borders between groups match.
## Returns {indices (global ids), error (object-space, sqrt of worst accumulated cost)}.
@warning_ignore("integer_division")
static func _simplify(vertices: PackedVector3Array, tris: PackedInt32Array, target_tris: int) -> Dictionary:
	var l2g := PackedInt32Array()
	var g2l: Dictionary = {}
	var t := PackedInt32Array()
	for i in tris.size():
		var g: int = tris[i]
		var li: int
		if g2l.has(g):
			li = g2l[g]
		else:
			li = l2g.size()
			g2l[g] = li
			l2g.append(g)
		t.append(li)
	var n: int = l2g.size()
	var pos := PackedVector3Array()
	pos.resize(n)
	for i in n:
		pos[i] = vertices[l2g[i]]
	var tc: int = t.size() / 3
	var edge_count: Dictionary = {}
	for f in tc:
		for e in 3:
			var key := _edge_key(t[f * 3 + e], t[f * 3 + (e + 1) % 3])
			edge_count[key] = int(edge_count.get(key, 0)) + 1
	var locked := PackedByteArray()
	locked.resize(n)
	for f in tc:
		for e in 3:
			var a: int = t[f * 3 + e]
			var b: int = t[f * 3 + (e + 1) % 3]
			if int(edge_count[_edge_key(a, b)]) != 2:
				locked[a] = 1
				locked[b] = 1
	var q := PackedFloat64Array()
	q.resize(n * 10)
	for f in tc:
		var pa: Vector3 = pos[t[f * 3]]
		var pb: Vector3 = pos[t[f * 3 + 1]]
		var pcv: Vector3 = pos[t[f * 3 + 2]]
		var nrm: Vector3 = (pb - pa).cross(pcv - pa)
		if nrm.length_squared() < 1.0e-24:
			continue
		nrm = nrm.normalized()
		var d: float = -nrm.dot(pa)
		for e in 3:
			_add_plane(q, t[f * 3 + e], nrm.x, nrm.y, nrm.z, d)
	var err2: float = 0.0
	var cur_tris: int = tc
	var redirect := PackedInt32Array()
	redirect.resize(n)
	while cur_tris > target_tris and cur_tris > 0:
		# CSR vertex -> triangles
		var off := PackedInt32Array()
		off.resize(n + 1)
		for i in t.size():
			off[t[i] + 1] += 1
		for i in n:
			off[i + 1] += off[i]
		var fill := off.duplicate()
		var vt := PackedInt32Array()
		vt.resize(t.size())
		for f in cur_tris:
			for e in 3:
				var v: int = t[f * 3 + e]
				vt[fill[v]] = f
				fill[v] += 1
		# candidate edges
		var cands: Array = []
		var seen: Dictionary = {}
		for f in cur_tris:
			for e in 3:
				var a: int = t[f * 3 + e]
				var b: int = t[f * 3 + (e + 1) % 3]
				var key := _edge_key(a, b)
				if seen.has(key):
					continue
				seen[key] = true
				var from: int
				var dest: int
				if locked[a] == 1 and locked[b] == 1:
					continue
				elif locked[a] == 1:
					from = b
					dest = a
				elif locked[b] == 1:
					from = a
					dest = b
				else:
					var cab: float = _q_cost(q, a, b, pos[b])
					var cba: float = _q_cost(q, a, b, pos[a])
					if cab <= cba:
						from = a
						dest = b
					else:
						from = b
						dest = a
				cands.append([_q_cost(q, from, dest, pos[dest]), from, dest])
		cands.sort()
		for i in n:
			redirect[i] = i
		var touched := PackedByteArray()
		touched.resize(n)
		var did: int = 0
		for cd in cands:
			if cur_tris <= target_tris:
				break
			var from: int = cd[1]
			var dest: int = cd[2]
			if touched[from] == 1 or touched[dest] == 1:
				continue
			var shared: int = 0
			var nbr: Dictionary = {}
			var ok: bool = true
			var pd: Vector3 = pos[dest]
			for k in range(off[from], off[from + 1]):
				var f: int = vt[k]
				var has_dest: bool = false
				for e in 3:
					var v: int = t[f * 3 + e]
					if v == dest:
						has_dest = true
					elif v != from:
						nbr[v] = true
				if has_dest:
					shared += 1
					continue
				var p0: Vector3 = pos[t[f * 3]]
				var p1: Vector3 = pos[t[f * 3 + 1]]
				var p2: Vector3 = pos[t[f * 3 + 2]]
				var n_old: Vector3 = (p1 - p0).cross(p2 - p0)
				if t[f * 3] == from:
					p0 = pd
				elif t[f * 3 + 1] == from:
					p1 = pd
				else:
					p2 = pd
				var n_new: Vector3 = (p1 - p0).cross(p2 - p0)
				if n_new.length_squared() < 1.0e-24:
					ok = false
					break
				if n_old.length_squared() > 1.0e-24 and n_old.normalized().dot(n_new.normalized()) < 0.2:
					ok = false
					break
			if not ok or shared == 0:
				continue
			var common: Dictionary = {}
			for k in range(off[dest], off[dest + 1]):
				var f: int = vt[k]
				for e in 3:
					var v: int = t[f * 3 + e]
					if v != dest and nbr.has(v):
						common[v] = true
			if common.size() != shared:
				continue
			redirect[from] = dest
			for k in range(off[from], off[from + 1]):
				var f: int = vt[k]
				for e in 3:
					touched[t[f * 3 + e]] = 1
			for k in range(off[dest], off[dest + 1]):
				var f: int = vt[k]
				for e in 3:
					touched[t[f * 3 + e]] = 1
			var qa: int = from * 10
			var qb: int = dest * 10
			for j in 10:
				q[qb + j] += q[qa + j]
			err2 = maxf(err2, float(cd[0]))
			cur_tris -= shared
			did += 1
		if did == 0:
			break
		var nt := PackedInt32Array()
		for f in t.size() / 3:
			var a: int = redirect[t[f * 3]]
			var b: int = redirect[t[f * 3 + 1]]
			var c: int = redirect[t[f * 3 + 2]]
			if a == b or b == c or a == c:
				continue
			nt.append(a)
			nt.append(b)
			nt.append(c)
		t = nt
		cur_tris = t.size() / 3
	var out := PackedInt32Array()
	out.resize(t.size())
	for i in t.size():
		out[i] = l2g[t[i]]
	return {"indices": out, "error": sqrt(err2)}
