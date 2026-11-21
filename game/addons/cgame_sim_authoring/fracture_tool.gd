extends RefCounted
## Fracture authoring: preview, exploded inspection view, hierarchical levels
## (destruction LOD) and precomputed-fragment asset save/load.
## Original code over res://scripts/shared/voronoi_fracture.gd. Hierarchy uses plain
## k-means (Lloyd 1982) on cell centroids with deterministic farthest-point seeding.

const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")


## Voronoi cells (PackedVector3Array hulls) for a box centred at the origin.
func preview(size: Vector3, piece_count: int, seed: int, impact: Vector3 = Vector3.INF, bias: float = 0.0) -> Array:
	var sites := VoronoiFracture.random_sites(size, maxi(piece_count, 1), seed, impact, bias)
	return VoronoiFracture.fracture_box(size, sites)


## One Transform3D per cell: translation pushes the piece away from the box centre.
func explode_view(cells: Array, factor: float, center: Vector3 = Vector3.ZERO) -> Array:
	var out: Array = []
	for cell in cells:
		var pts: PackedVector3Array = cell
		var c := VoronoiFracture.centroid(pts)
		out.append(Transform3D(Basis.IDENTITY, (c - center) * factor))
	return out


## Hierarchical levels. `counts` are piece counts per level; the finest (largest) is fractured
## for real, coarser levels cluster those cells into parents. Returned finest first:
## [{"count": int, "cells": Array (hull points), "members": Array[PackedInt32Array]
##   (finest cell indices per piece), "parent_of": PackedInt32Array (finest index -> piece)}]
func levels(size: Vector3, counts: PackedInt32Array, seed: int) -> Array:
	var sorted: Array = []
	for c in counts:
		sorted.append(maxi(c, 1))
	sorted.sort()
	sorted.reverse()
	var out: Array = []
	if sorted.is_empty():
		return out
	var finest: Array = preview(size, sorted[0] as int, seed)
	var centroids := PackedVector3Array()
	for cell in finest:
		centroids.append(VoronoiFracture.centroid(cell as PackedVector3Array))
	for lv in sorted.size():
		var k: int = mini(sorted[lv] as int, finest.size())
		var assign: PackedInt32Array
		if lv == 0:
			assign = PackedInt32Array()
			for i in finest.size():
				assign.append(i)
			k = finest.size()
		else:
			assign = _kmeans(centroids, k)
		var members: Array = []
		var merged: Array = []
		for p in k:
			members.append(PackedInt32Array())
			merged.append(PackedVector3Array())
		for i in finest.size():
			var piece: int = assign[i]
			var mem: PackedInt32Array = members[piece]
			mem.append(i)
			members[piece] = mem
			var mg: PackedVector3Array = merged[piece]
			mg.append_array(finest[i] as PackedVector3Array)
			merged[piece] = mg
		out.append({"count": k, "cells": merged, "members": members, "parent_of": assign})
	return out


func _kmeans(pts: PackedVector3Array, k: int) -> PackedInt32Array:
	var n: int = pts.size()
	var centers := PackedVector3Array()
	centers.append(pts[0])
	while centers.size() < k:
		var best: int = 0
		var best_d: float = -1.0
		for i in n:
			var dmin: float = INF
			for c in centers:
				dmin = minf(dmin, pts[i].distance_squared_to(c))
			if dmin > best_d:
				best_d = dmin
				best = i
		centers.append(pts[best])
	var assign := PackedInt32Array()
	assign.resize(n)
	for _it in 12:
		for i in n:
			var bi: int = 0
			var bd: float = INF
			for c in k:
				var d: float = pts[i].distance_squared_to(centers[c])
				if d < bd:
					bd = d
					bi = c
			assign[i] = bi
		var sums := PackedVector3Array()
		sums.resize(k)
		var cnt := PackedInt32Array()
		cnt.resize(k)
		for i in n:
			sums[assign[i]] += pts[i]
			cnt[assign[i]] += 1
		for c in k:
			if cnt[c] > 0:
				centers[c] = sums[c] / float(cnt[c])
	# Every cluster must own at least one cell (a seed always stays assigned to its own point).
	for c in k:
		var has: bool = false
		for i in n:
			if assign[i] == c:
				has = true
				break
		if not has:
			var far: int = 0
			var fd: float = -1.0
			for i in n:
				var d2: float = pts[i].distance_squared_to(centers[assign[i]])
				if d2 > fd:
					fd = d2
					far = i
			assign[far] = c
	return assign


## Saves precomputed fragments. ".json" => text JSON, anything else => var_to_bytes.
func save_asset(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	if path.ends_with(".json"):
		f.store_string(JSON.stringify(_enc(data)))
	else:
		f.store_buffer(var_to_bytes(data))
	f.close()
	return true


## Loads an asset written by save_asset. Returns {} on any failure.
func load_asset(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	if path.ends_with(".json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			return {}
		var dec: Variant = _dec(parsed)
		if dec is Dictionary:
			return dec as Dictionary
		return {}
	var bytes := FileAccess.get_file_as_bytes(path)
	var v: Variant = bytes_to_var(bytes)
	if v is Dictionary:
		return v as Dictionary
	return {}


# Typed JSON encoding so Vector3 / packed arrays / ints survive a text round trip.
func _enc(v: Variant) -> Variant:
	if v is PackedVector3Array:
		var flat: Array = []
		for p in (v as PackedVector3Array):
			flat.append_array([p.x, p.y, p.z])
		return {"$v3": flat}
	if v is PackedInt32Array:
		return {"$i32": Array(v as PackedInt32Array)}
	if v is Vector3:
		var vv: Vector3 = v
		return {"$vec3": [vv.x, vv.y, vv.z]}
	if v is int:
		return {"$int": v}
	if v is Dictionary:
		var d: Dictionary = {}
		for key in (v as Dictionary):
			d[key] = _enc((v as Dictionary)[key])
		return d
	if v is Array:
		var a: Array = []
		for e in (v as Array):
			a.append(_enc(e))
		return a
	return v


func _dec(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("$v3"):
			var flat: Array = d["$v3"]
			var out := PackedVector3Array()
			var i: int = 0
			while i + 2 < flat.size():
				out.append(Vector3(flat[i] as float, flat[i + 1] as float, flat[i + 2] as float))
				i += 3
			return out
		if d.has("$i32"):
			var ia := PackedInt32Array()
			for e in (d["$i32"] as Array):
				ia.append(int(e as float))
			return ia
		if d.has("$vec3"):
			var t: Array = d["$vec3"]
			return Vector3(t[0] as float, t[1] as float, t[2] as float)
		if d.has("$int"):
			return int(d["$int"] as float)
		var o: Dictionary = {}
		for key in d:
			o[key] = _dec(d[key])
		return o
	if v is Array:
		var a: Array = []
		for e in (v as Array):
			a.append(_dec(e))
		return a
	return v
