extends RefCounted
## Meshlets, cluster LOD DAG, screen-space-error cut and per-cluster culling.

const Meshlets = preload("res://scripts/shared/meshlets.gd")
const ClusterLod = preload("res://scripts/shared/cluster_lod.gd")

const FOV := 1.0471976  # 60 degrees
const SCREEN_H := 1080.0


## UV sphere with single-vertex poles, welded, Godot (clockwise-front) winding.
static func _sphere(rings: int, segs: int, radius: float) -> Dictionary:
	var verts := PackedVector3Array()
	verts.append(Vector3(0, radius, 0))
	for r in range(1, rings):
		var th: float = PI * float(r) / float(rings)
		for s in segs:
			var ph: float = TAU * float(s) / float(segs)
			verts.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * radius)
	verts.append(Vector3(0, -radius, 0))
	var bottom: int = verts.size() - 1
	var idx := PackedInt32Array()
	for s in segs:
		var s2: int = (s + 1) % segs
		_tri(verts, idx, 0, 1 + s, 1 + s2)
	for r in range(0, rings - 2):
		for s in segs:
			var s2: int = (s + 1) % segs
			var a: int = 1 + r * segs + s
			var b: int = 1 + r * segs + s2
			var c: int = 1 + (r + 1) * segs + s
			var d: int = 1 + (r + 1) * segs + s2
			_tri(verts, idx, a, b, c)
			_tri(verts, idx, b, d, c)
	var last: int = 1 + (rings - 2) * segs
	for s in segs:
		var s2: int = (s + 1) % segs
		_tri(verts, idx, last + s, last + s2, bottom)
	return {"vertices": verts, "indices": idx}


static func _tri(verts: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int) -> void:
	var n: Vector3 = (verts[c] - verts[a]).cross(verts[b] - verts[a])
	var cen: Vector3 = (verts[a] + verts[b] + verts[c]) / 3.0
	if n.dot(cen) < 0.0:
		var tmp: int = b
		b = c
		c = tmp
	idx.append(a)
	idx.append(b)
	idx.append(c)


@warning_ignore("integer_division")
static func _area(verts: PackedVector3Array, idx: PackedInt32Array) -> float:
	var total: float = 0.0
	for f in idx.size() / 3:
		var a: Vector3 = verts[idx[f * 3]]
		total += 0.5 * (verts[idx[f * 3 + 1]] - a).cross(verts[idx[f * 3 + 2]] - a).length()
	return total


## Returns {open: edges used once, over: edges used more than twice}.
@warning_ignore("integer_division")
static func _edge_stats(idx: PackedInt32Array) -> Dictionary:
	var counts: Dictionary = {}
	for f in idx.size() / 3:
		for e in 3:
			var a: int = idx[f * 3 + e]
			var b: int = idx[f * 3 + (e + 1) % 3]
			var key: int = (mini(a, b) << 32) | maxi(a, b)
			counts[key] = int(counts.get(key, 0)) + 1
	var open: int = 0
	var over: int = 0
	for k in counts:
		var c: int = counts[k]
		if c == 1:
			open += 1
		elif c > 2:
			over += 1
	return {"open": open, "over": over}


static func _cut_indices(h: Dictionary, cut: PackedInt32Array) -> PackedInt32Array:
	var clusters: Array = h["clusters"]
	var out := PackedInt32Array()
	for id in cut:
		var c: Dictionary = clusters[id]
		var ci: PackedInt32Array = c["indices"]
		out.append_array(ci)
	return out


func run(t) -> void:
	var mesh: Dictionary = _sphere(36, 48, 1.0)
	var verts: PackedVector3Array = mesh["vertices"]
	var idx: PackedInt32Array = mesh["indices"]
	@warning_ignore("integer_division")
	var tri_total: int = idx.size() / 3
	var area0: float = _area(verts, idx)
	t.check(tri_total > 3000, "test sphere has a few thousand triangles (%d)" % tri_total)

	t.current = "meshlets"
	var ml: Array = Meshlets.build_meshlets(verts, idx)
	t.check(ml.size() >= tri_total / 124, "meshlet count is plausible (%d)" % ml.size())
	var seen: Dictionary = {}
	var limits_ok: bool = true
	var bounds_ok: bool = true
	var covered: int = 0
	for i in ml.size():
		var m: Dictionary = ml[i]
		var li: PackedInt32Array = m["indices"]
		var vids: PackedInt32Array = m["vertex_ids"]
		@warning_ignore("integer_division")
		var mtris: int = li.size() / 3
		if vids.size() > 64 or mtris > 124:
			limits_ok = false
		var ctr: Vector3 = m["bounds_center"]
		var rad: float = m["bounds_radius"]
		for v in vids:
			if verts[v].distance_to(ctr) > rad + 0.0001:
				bounds_ok = false
		for f in mtris:
			var tri: Array = [vids[li[f * 3]], vids[li[f * 3 + 1]], vids[li[f * 3 + 2]]]
			tri.sort()
			var key: String = "%d_%d_%d" % [tri[0], tri[1], tri[2]]
			seen[key] = int(seen.get(key, 0)) + 1
			covered += 1
	t.check(limits_ok, "meshlets respect 64 vertices / 124 triangles")
	t.check(bounds_ok, "bounding spheres contain all meshlet vertices")
	t.eq(covered, tri_total, "meshlets contain every triangle")
	var once: bool = seen.size() == tri_total
	for k in seen:
		if int(seen[k]) != 1:
			once = false
	t.check(once, "each triangle appears in exactly one meshlet")
	var small: Array = Meshlets.build_meshlets(verts, idx, 12, 8)
	var small_ok: bool = true
	for i in small.size():
		var sm: Dictionary = small[i]
		var sv: PackedInt32Array = sm["vertex_ids"]
		var si: PackedInt32Array = sm["indices"]
		if sv.size() > 12 or si.size() > 24:
			small_ok = false
	t.check(small_ok, "custom small limits respected")

	t.current = "meshlet culling"
	var cam := Vector3(0, 0, 5)
	var culled: int = 0
	var cull_valid: bool = true
	var near_idx: int = 0
	var near_d: float = INF
	for i in ml.size():
		var m: Dictionary = ml[i]
		var ctr: Vector3 = m["bounds_center"]
		if ctr.distance_to(cam) < near_d:
			near_d = ctr.distance_to(cam)
			near_idx = i
		if Meshlets.cone_cull(m, cam):
			culled += 1
			var li: PackedInt32Array = m["indices"]
			var vids: PackedInt32Array = m["vertex_ids"]
			for f in li.size() / 3:
				var a: Vector3 = verts[vids[li[f * 3]]]
				var n: Vector3 = (verts[vids[li[f * 3 + 2]]] - a).cross(verts[vids[li[f * 3 + 1]]] - a)
				if n.dot(a - cam) < -0.0001:
					cull_valid = false
	t.check(culled > ml.size() / 4, "back side meshlets are cone-culled (%d of %d)" % [culled, ml.size()])
	t.check(culled < ml.size(), "front meshlets survive cone culling")
	t.check(cull_valid, "cone-culled meshlets contain no front-facing triangles")
	t.check(not Meshlets.cone_cull(ml[near_idx], cam), "nearest meshlet is not cone-culled")
	var cam_in := Vector3.ZERO
	var inside_culled: int = 0
	for i in ml.size():
		if Meshlets.cone_cull(ml[i], cam_in):
			inside_culled += 1
	t.check(inside_culled > 0, "camera inside sees only back faces, so meshlets are culled (%d)" % inside_culled)
	var box_in: Array[Plane] = [
		Plane(Vector3.RIGHT, 10.0), Plane(Vector3.LEFT, 10.0), Plane(Vector3.UP, 10.0),
		Plane(Vector3.DOWN, 10.0), Plane(Vector3.BACK, 10.0), Plane(Vector3.FORWARD, 10.0)]
	var box_out: Array[Plane] = [
		Plane(Vector3.RIGHT, 120.0), Plane(Vector3.LEFT, -100.0), Plane(Vector3.UP, 10.0),
		Plane(Vector3.DOWN, 10.0), Plane(Vector3.BACK, 10.0), Plane(Vector3.FORWARD, 10.0)]
	var half: Array[Plane] = [Plane(Vector3.RIGHT, 0.0)]
	var in_culled: int = 0
	var out_culled: int = 0
	var half_culled: int = 0
	for i in ml.size():
		var m: Dictionary = ml[i]
		if Meshlets.frustum_cull(m, box_in):
			in_culled += 1
		if Meshlets.frustum_cull(m, box_out):
			out_culled += 1
		if Meshlets.frustum_cull(m, half):
			half_culled += 1
	t.eq(in_culled, 0, "frustum around the sphere culls nothing")
	t.eq(out_culled, ml.size(), "frustum away from the sphere culls everything")
	t.check(half_culled > 0 and half_culled < ml.size(), "half-space culls only meshlets on the far side (%d)" % half_culled)

	t.current = "cluster hierarchy"
	var h: Dictionary = ClusterLod.build_hierarchy(verts, idx, 4)
	var clusters: Array = h["clusters"]
	t.check(int(h["levels"]) >= 3, "hierarchy has several levels (%d)" % int(h["levels"]))
	var level_tris: Dictionary = {}
	var mono_ok: bool = true
	var sphere_ok: bool = true
	var limits2_ok: bool = true
	for i in clusters.size():
		var c: Dictionary = clusters[i]
		var ci: PackedInt32Array = c["indices"]
		var lv: int = c["level"]
		@warning_ignore("integer_division")
		var ctris: int = ci.size() / 3
		level_tris[lv] = int(level_tris.get(lv, 0)) + ctris
		var vids: PackedInt32Array = c["vertex_ids"]
		if ctris > 124 or vids.size() > 64:
			limits2_ok = false
		var e: float = c["error"]
		var pe: float = c["parent_error"]
		if pe < e:
			mono_ok = false
		if not is_inf(pe):
			var d: float = (c["lod_center"] as Vector3).distance_to(c["parent_center"])
			if d + float(c["lod_radius"]) > float(c["parent_radius"]) + 0.0001:
				sphere_ok = false
		var kids: PackedInt32Array = c["children"]
		for k in kids:
			var kc: Dictionary = clusters[k]
			if float(kc["error"]) > e or float(kc["parent_error"]) != e:
				mono_ok = false
	t.check(mono_ok, "parent error >= child error everywhere")
	t.check(sphere_ok, "parent LOD sphere contains child LOD sphere")
	t.check(limits2_ok, "re-split clusters respect meshlet limits")
	t.eq(int(level_tris[0]), tri_total, "level 0 holds the original triangles")
	t.check(int(level_tris[1]) < int(level_tris[0]) * 0.7, "level 1 is much coarser than level 0 (%d)" % int(level_tris[1]))
	t.check(int(level_tris[2]) < int(level_tris[1]), "level 2 is coarser than level 1")
	var root_count: int = (h["roots"] as PackedInt32Array).size()
	t.check(root_count > 0, "hierarchy has root clusters")

	t.current = "cut selection"
	var cam_near := Vector3(0, 0, 1.5)
	var exact: PackedInt32Array = ClusterLod.select_cut(h, cam_near, FOV, SCREEN_H, 0.0001)
	t.eq(ClusterLod.triangle_count(h, exact), tri_total, "zero tolerance cut is the full-detail mesh")
	t.near(_area(verts, _cut_indices(h, exact)), area0, 0.001, "full-detail cut area matches")
	var far_cut: PackedInt32Array = ClusterLod.select_cut(h, Vector3(0, 0, 400), FOV, SCREEN_H, 1.0)
	var near_cut: PackedInt32Array = ClusterLod.select_cut(h, Vector3(0, 0, 3), FOV, SCREEN_H, 1.0)
	var far_tris: int = ClusterLod.triangle_count(h, far_cut)
	var near_tris: int = ClusterLod.triangle_count(h, near_cut)
	t.check(far_tris > 0 and far_tris * 3 < near_tris, "far camera selects far fewer triangles (%d vs %d)" % [far_tris, near_tris])
	var prev: int = 1 << 30
	var shrinking: bool = true
	var cracks_ok: bool = true
	var area_ok: bool = true
	var unique_ok: bool = true
	for dist in [2.0, 6.0, 20.0, 60.0, 200.0, 800.0]:
		var cut: PackedInt32Array = ClusterLod.select_cut(h, Vector3(0, 0, dist), FOV, SCREEN_H, 1.0)
		var n_tris: int = ClusterLod.triangle_count(h, cut)
		if n_tris > prev:
			shrinking = false
		prev = n_tris
		var ci: PackedInt32Array = _cut_indices(h, cut)
		var stats: Dictionary = _edge_stats(ci)
		if int(stats["open"]) != 0 or int(stats["over"]) != 0:
			cracks_ok = false
			print("  cut@%s open=%d over=%d tris=%d" % [dist, stats["open"], stats["over"], n_tris])
		var ratio: float = _area(verts, ci) / area0
		if ratio > 1.001 or ratio < 0.85:
			area_ok = false
			print("  cut@%s area ratio %.4f" % [dist, ratio])
		var ids: Dictionary = {}
		for id in cut:
			ids[id] = true
		if ids.size() != cut.size():
			unique_ok = false
	t.check(shrinking, "triangle count never grows with distance")
	t.check(cracks_ok, "cuts are watertight (no open or over-shared edges)")
	t.check(area_ok, "cut surface area stays close to the original (no hole or overlap)")
	t.check(unique_ok, "cut has no duplicate clusters")

	t.current = "determinism"
	var h2: Dictionary = ClusterLod.build_hierarchy(verts, idx, 4)
	var c2: Array = h2["clusters"]
	t.eq(c2.size(), clusters.size(), "same cluster count on rebuild")
	var same: bool = c2.size() == clusters.size()
	if same:
		for i in clusters.size():
			var a: Dictionary = clusters[i]
			var b: Dictionary = c2[i]
			if (a["indices"] as PackedInt32Array) != (b["indices"] as PackedInt32Array) or float(a["error"]) != float(b["error"]):
				same = false
				break
	t.check(same, "rebuild gives identical clusters and errors")
	var cut_b: PackedInt32Array = ClusterLod.select_cut(h2, Vector3(0, 0, 3), FOV, SCREEN_H, 1.0)
	t.check(cut_b == near_cut, "same cut for the same camera")

	t.current = "CPU cut assembly preserves full source vertex streams"
	var source_arrays: Array = []
	source_arrays.resize(Mesh.ARRAY_MAX)
	source_arrays[Mesh.ARRAY_VERTEX] = verts
	source_arrays[Mesh.ARRAY_INDEX] = idx
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	for i in verts.size():
		uv.append(Vector2(float(i % 11) / 11.0, float(i % 7) / 7.0))
		colors.append(Color(float(i % 3) / 3.0, 0.65, 0.8))
		normals.append(verts[i].normalized())
	source_arrays[Mesh.ARRAY_TEX_UV] = uv
	source_arrays[Mesh.ARRAY_COLOR] = colors
	source_arrays[Mesh.ARRAY_NORMAL] = normals
	var selected: Array = ClusterLod.build_cut_arrays(source_arrays, h, far_cut)
	t.eq(selected.size(), Mesh.ARRAY_MAX, "selected cut returns complete Mesh arrays")
	if selected.size() == Mesh.ARRAY_MAX:
		t.eq(selected[Mesh.ARRAY_TEX_UV], uv, "UV coordinates survive indexed simplification")
		t.eq(selected[Mesh.ARRAY_NORMAL], normals, "normals remain linked to original vertex IDs")
		t.eq(selected[Mesh.ARRAY_COLOR], colors, "material vertex colors survive")
		t.eq(selected[Mesh.ARRAY_INDEX].size(), far_tris * 3,
			"assembled material-preserving cut has the exact selected triangle count")
	t.eq(ClusterLod.build_cut_arrays(source_arrays, h, PackedInt32Array()), [],
		"an empty cut fails closed")
	t.eq(source_arrays[Mesh.ARRAY_INDEX], idx, "original triangle source is unchanged")
