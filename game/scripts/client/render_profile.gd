extends RefCounted
## Benchmark-only render breakdown (visible vs shadow passes). For per-pass GPU time run the client with --gpu-profile.
## (online_main --screenshot) to choose optimizations from measurements instead of guesses.


## Visible vs shadow objects/primitives/draw calls for a viewport.
static func pass_counts(viewport: Viewport) -> Dictionary:
	var rid := viewport.get_viewport_rid()
	var out := {}
	for kind in [["visible", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE],
			["shadow", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW],
			["canvas", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS]]:
		out[kind[0]] = {
			"objects": RenderingServer.viewport_get_render_info(rid, kind[1], RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			"primitives": RenderingServer.viewport_get_render_info(rid, kind[1], RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			"draws": RenderingServer.viewport_get_render_info(rid, kind[1], RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		}
	return out



## Which expensive features the run actually used (benchmarks compare like with like).
static func settings(viewport: Viewport, environment: Environment, quality_level: int) -> Dictionary:
	var out := {"quality": quality_level, "scale": snappedf(viewport.scaling_3d_scale, 0.01),
		"scaling_mode": int(viewport.scaling_3d_mode), "msaa": int(viewport.msaa_3d),
		"taa": viewport.use_taa, "size": viewport.get_visible_rect().size,
		"positional_shadow_atlas": viewport.positional_shadow_atlas_size}
	if environment != null:
		for key in ["ssao_enabled", "ssil_enabled", "ssr_enabled", "sdfgi_enabled", "glow_enabled",
				"volumetric_fog_enabled"]:
			out[key] = environment.get(key)
	return out


static func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		var verts = arrays[Mesh.ARRAY_VERTEX]
		tris += (indices.size() if indices != null and indices.size() > 0 else (verts.size() if verts != null else 0)) / 3
	return tris


## Triangles (full LOD, before engine LOD) of geometry in the camera frustum, grouped by the scene branch it
## belongs to: [[group, triangles, instances], ...] largest first. Benchmark-only: it walks the whole tree.
static func geometry_by_group(root: Node, camera: Camera3D, limit: int = 14) -> Array:
	var groups := {}
	var cache := {}
	var planes: Array[Plane] = camera.get_frustum()
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var inside := true
		for p in planes:
			var c := box.get_center()
			var e := box.size * 0.5
			var r: float = absf(p.normal.x) * e.x + absf(p.normal.y) * e.y + absf(p.normal.z) * e.z
			if p.distance_to(c) > r:
				inside = false
				break
		if not inside:
			continue
		var tris := 0
		var count := 1
		if g is MeshInstance3D:
			var m: Mesh = (g as MeshInstance3D).mesh
			if not cache.has(m):
				cache[m] = _mesh_triangles(m)
			tris = cache[m]
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			if not cache.has(mm.mesh):
				cache[mm.mesh] = _mesh_triangles(mm.mesh)
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris = int(cache[mm.mesh]) * count
		else:
			continue
		# Group by the child of the scene root that owns it, refined one level for the big containers.
		var path: NodePath = root.get_path_to(g)
		var key: String = str(path.get_name(0)) if path.get_name_count() > 0 else "?"
		if key.contains("WorldStreamer") or key.begins_with("Pcg"):
			# Inside streamed chunks group by what the geometry is, not which chunk holds it.
			var m: Mesh = (g as MeshInstance3D).mesh if g is MeshInstance3D else ((g as MultiMeshInstance3D).multimesh.mesh if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null else null)
			var per: int = int(cache.get(m, 0))
			var label: String = m.resource_path.get_file() if m != null and m.resource_path != "" else (str(m.resource_name) if m != null and m.resource_name != "" else str(g.name).rstrip("0123456789@"))
			if g.has_meta("aa_scenery_kind"):
				label = "scenery:" + str(g.get_meta("aa_scenery_kind"))
			key = "%s (%d tris each)" % [label.left(60), per]
		elif path.get_name_count() > 2:
			key += "/" + str(path.get_name(1)).left(24)
		var row: Array = groups.get(key, [0, 0])
		row[0] += tris
		row[1] += count
		groups[key] = row
	var rows: Array = []
	for key in groups:
		rows.append([key, groups[key][0], groups[key][1]])
	rows.sort_custom(func(a, b) -> bool: return int(a[1]) > int(b[1]))
	return rows.slice(0, limit)


## How many MultiMesh instances the engine draws (whole MultiMesh visible and within its visibility range)
## versus how many would survive a per-instance frustum + distance test. Benchmark-only estimate of what
## GPU per-instance culling would save. Returns {"drawn": int, "needed": int}.
static func instance_culling_estimate(root: Node, camera: Camera3D) -> Dictionary:
	var planes: Array[Plane] = camera.get_frustum()
	var eye: Vector3 = camera.global_position
	var drawn := 0
	var needed := 0
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if not mmi.is_visible_in_tree() or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var box: AABB = mmi.global_transform * mmi.get_aabb()
		var limit: float = mmi.visibility_range_end if mmi.visibility_range_end > 0.0 else INF
		var nearest: Vector3 = eye.clamp(box.position, box.end)
		if nearest.distance_to(eye) > limit or not _box_in_planes(box, planes):
			continue
		var count: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		var local: AABB = mm.mesh.get_aabb()
		drawn += count
		for i in count:
			var xf: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
			var center: Vector3 = xf * local.get_center()
			var radius: float = (local.size * 0.5).length() * maxf(xf.basis.get_scale().x, maxf(xf.basis.get_scale().y, xf.basis.get_scale().z))
			if center.distance_to(eye) - radius > limit:
				continue
			var inside := true
			for p in planes:
				if p.distance_to(center) > radius:
					inside = false
					break
			if inside:
				needed += 1
	return {"drawn": drawn, "needed": needed}


static func _box_in_planes(box: AABB, planes: Array[Plane]) -> bool:
	var c := box.get_center()
	var e := box.size * 0.5
	for p in planes:
		if p.distance_to(c) > absf(p.normal.x) * e.x + absf(p.normal.y) * e.y + absf(p.normal.z) * e.z:
			return false
	return true
