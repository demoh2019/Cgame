extends RefCounted
## Meshlet (cluster) building and per-cluster culling, a CPU port of the ideas
## behind virtualized geometry (Nanite-style clusters).
##
## Credits / sources (ideas and formulas re-implemented from scratch, no code copied):
##   - meshoptimizer by Arseny Kapoulkine, MIT license (meshlet building, normal-cone
##     bounds and the cone culling test: dot(center - cam, axis) >= cutoff*|center - cam| + radius).
##   - "A Deep Dive into Nanite Virtualized Geometry", Karis et al., SIGGRAPH 2021.
##   - Bevy virtual geometry write-up (MIT / Apache-2.0), used for background only.
##
## Conventions: triangle winding is Godot's (front faces are clockwise), so the
## geometric normal that faces the viewer is (c - a) x (b - a). Meshlet dictionaries hold:
##   indices        PackedInt32Array  triangle list, local indices into vertex_ids
##   vertex_ids     PackedInt32Array  indices into the source vertex array
##   bounds_center  Vector3, bounds_radius float (bounding sphere containing every vertex)
##   cone_axis      Vector3, cone_cutoff float (normal cone; cutoff 1.0 = never cone-culled)


static func _edge_key(a: int, b: int) -> int:
	if a > b:
		return (b << 32) | a
	return (a << 32) | b


## Greedy adjacency-based clustering. Seeds grow by repeatedly taking the frontier
## triangle that adds the fewest new vertices, ties broken by distance to the centroid.
@warning_ignore("integer_division")
static func build_meshlets(vertices: PackedVector3Array, indices: PackedInt32Array, max_vertices: int = 64, max_triangles: int = 124) -> Array:
	var result: Array = []
	var tri_count: int = indices.size() / 3
	if tri_count == 0:
		return result
	var mv: int = maxi(max_vertices, 3)
	var mt: int = maxi(max_triangles, 1)
	var edge_tris: Dictionary = {}
	for f in tri_count:
		for e in 3:
			var key := _edge_key(indices[f * 3 + e], indices[f * 3 + (e + 1) % 3])
			if edge_tris.has(key):
				var lst: PackedInt32Array = edge_tris[key]
				lst.append(f)
				edge_tris[key] = lst
			else:
				edge_tris[key] = PackedInt32Array([f])
	var used := PackedByteArray()
	used.resize(tri_count)
	var spill: Dictionary = {}
	var scan: int = 0
	var remaining: int = tri_count
	while remaining > 0:
		var seed_tri: int = -1
		while seed_tri < 0 and not spill.is_empty():
			var sk: int = spill.keys()[0]
			spill.erase(sk)
			if used[sk] == 0:
				seed_tri = sk
		if seed_tri < 0:
			while used[scan] != 0:
				scan += 1
			seed_tri = scan
		var local_of: Dictionary = {}
		var vids := PackedInt32Array()
		var lidx := PackedInt32Array()
		var frontier: Dictionary = {}
		var csum := Vector3.ZERO
		var ccount: int = 0
		var cur: int = seed_tri
		while cur >= 0:
			used[cur] = 1
			remaining -= 1
			frontier.erase(cur)
			var tsum := Vector3.ZERO
			for e in 3:
				var vid: int = indices[cur * 3 + e]
				var li: int
				if local_of.has(vid):
					li = local_of[vid]
				else:
					li = vids.size()
					local_of[vid] = li
					vids.append(vid)
				lidx.append(li)
				tsum += vertices[vid]
			csum += tsum / 3.0
			ccount += 1
			for e in 3:
				var key := _edge_key(indices[cur * 3 + e], indices[cur * 3 + (e + 1) % 3])
				var lst: PackedInt32Array = edge_tris[key]
				for nt in lst:
					if used[nt] == 0:
						frontier[nt] = true
			if ccount >= mt:
				break
			var centroid: Vector3 = csum / float(ccount)
			var best: int = -1
			var best_nv: int = 99
			var best_d: float = INF
			for k in frontier:
				var ft: int = k
				var nv: int = 0
				for e in 3:
					if not local_of.has(indices[ft * 3 + e]):
						nv += 1
				if vids.size() + nv > mv or nv > best_nv:
					continue
				var tc: Vector3 = (vertices[indices[ft * 3]] + vertices[indices[ft * 3 + 1]] + vertices[indices[ft * 3 + 2]]) / 3.0
				var d: float = tc.distance_squared_to(centroid)
				if nv < best_nv or d < best_d:
					best = ft
					best_nv = nv
					best_d = d
			cur = best
		for k in frontier:
			var fk: int = k
			if used[fk] == 0:
				spill[fk] = true
		result.append(_finish(vertices, vids, lidx))
	return result


@warning_ignore("integer_division")
static func _finish(vertices: PackedVector3Array, vids: PackedInt32Array, lidx: PackedInt32Array) -> Dictionary:
	var lo: Vector3 = vertices[vids[0]]
	var hi: Vector3 = lo
	for v in vids:
		var p: Vector3 = vertices[v]
		lo = lo.min(p)
		hi = hi.max(p)
	var center: Vector3 = (lo + hi) * 0.5
	var radius: float = 0.0
	for v in vids:
		radius = maxf(radius, center.distance_to(vertices[v]))
	var normals := PackedVector3Array()
	var sum := Vector3.ZERO
	for f in lidx.size() / 3:
		var a: Vector3 = vertices[vids[lidx[f * 3]]]
		var b: Vector3 = vertices[vids[lidx[f * 3 + 1]]]
		var c: Vector3 = vertices[vids[lidx[f * 3 + 2]]]
		var n: Vector3 = (c - a).cross(b - a)
		if n.length_squared() < 1.0e-24:
			continue
		n = n.normalized()
		normals.append(n)
		sum += n
	var axis := Vector3.ZERO
	var cutoff: float = 1.0
	if sum.length_squared() > 1.0e-12:
		var ax: Vector3 = sum.normalized()
		var mindp: float = 1.0
		for n in normals:
			mindp = minf(mindp, ax.dot(n))
		if mindp > 0.1:
			axis = ax
			cutoff = sqrt(maxf(1.0 - mindp * mindp, 0.0))
	return {
		"indices": lidx,
		"vertex_ids": vids,
		"bounds_center": center,
		"bounds_radius": radius,
		"cone_axis": axis,
		"cone_cutoff": cutoff,
	}


## True when every triangle of the meshlet faces away from camera_pos (safe to skip).
static func cone_cull(meshlet: Dictionary, camera_pos: Vector3) -> bool:
	var axis: Vector3 = meshlet["cone_axis"]
	var cutoff: float = meshlet["cone_cutoff"]
	var center: Vector3 = meshlet["bounds_center"]
	var radius: float = meshlet["bounds_radius"]
	var to_c: Vector3 = center - camera_pos
	return to_c.dot(axis) >= cutoff * to_c.length() + radius


## True when the bounding sphere lies fully outside one plane. Planes use outward
## normals (the Camera3D.get_frustum() convention): inside means distance_to() <= 0.
static func frustum_cull(meshlet: Dictionary, planes: Array[Plane]) -> bool:
	var center: Vector3 = meshlet["bounds_center"]
	var radius: float = meshlet["bounds_radius"]
	for p in planes:
		if p.distance_to(center) > radius:
			return true
	return false
