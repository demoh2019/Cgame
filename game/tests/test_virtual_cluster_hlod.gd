extends RefCounted
## Real PCG HLOD surface from the engine's cluster DAG, preserving PBR data.
## Native class is optional; the gameplay must still run on stock Godot.
const PcgWorldDressing = preload("res://scripts/client/pcg_world_dressing.gd")


static func _dense_asset() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.resource_name = "PcgClusterGrid"
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	var side := 20
	for z in side + 1:
		for x in side + 1:
			vertices.append(Vector3(float(x) * 0.15, sin(float(x) * 0.2) * cos(float(z) * 0.25) * 0.2, float(z) * 0.15))
			normals.append(Vector3.UP)
			uvs.append(Vector2(float(x) / float(side), float(z) / float(side)))
			colors.append(Color(0.4, 0.6, 0.3))
			tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, -1.0]))
	for z in side:
		for x in side:
			var a: int = z * (side + 1) + x
			indices.append_array(PackedInt32Array([a, a + side + 1, a + 1,
				a + 1, a + side + 1, a + side + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.6, 0.3)
	material.metallic = 0.35
	material.roughness = 0.28
	mesh.surface_set_material(0, material)
	return mesh


func run(t) -> void:
	t.current = "PCG distant cluster silhouettes and native PBR"
	t.eq(PcgWorldDressing.proxy_for(null), null, "null asset stays null")
	var mesh: ArrayMesh = _dense_asset()
	var original: Array = mesh.surface_get_arrays(0)
	var original_indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	var proxy: Mesh = PcgWorldDressing.proxy_for(mesh)
	t.check(proxy != null, "every cosmetic mesh gets a far proxy")
	t.check(PcgWorldDressing.proxy_for(mesh) == proxy, "HLOD prepared only once per source")
	t.check(proxy.get_surface_count() == 1, "proxy has one valid drawable surface")
	if ClassDB.class_exists("CgameClusterLOD"):
		var native: Object = ClassDB.instantiate("CgameClusterLOD")
		t.check(native.has_method("build_cut_surface"), "native engine exports draw-ready cluster cut")
		var h: Dictionary = native.call("build_hierarchy", original[Mesh.ARRAY_VERTEX], original_indices, 5)
		t.check(not h.is_empty(), "native hierarchy created from actual source mesh")
		var cut: PackedInt32Array = h.get("roots", PackedInt32Array())
		var surface: Array = native.call("build_cut_surface", h, cut, original)
		t.eq(surface.size(), Mesh.ARRAY_MAX, "renderable cluster cut is an ArrayMesh surface")
		if surface.size() == Mesh.ARRAY_MAX:
			for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
				Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
				t.eq(surface[slot], original[slot], "PBR source attribute %d preserved byte-for-byte" % slot)
			var selected: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
			t.check(selected.size() > 0 and selected.size() <= original_indices.size(),
				"cluster surface uses bounded source vertex IDs")
		var cluster_proxy: Mesh = PcgWorldDressing.cluster_proxy_for(mesh)
		if cluster_proxy != null:
			t.check(proxy.surface_get_material(0) == mesh.surface_get_material(0),
				"PCG proxy keeps authored metallic/roughness PBR material")
			t.check(proxy.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() < original_indices.size(),
				"distant GPU mesh rasterizes fewer triangles")
			t.check(proxy.resource_name.ends_with("_ClusterHLOD"),
				"selected native proxy exposes its origin")
		else:
			t.check(proxy.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 36,
				"unsimplifiable native source safely retains 12-triangle box")
	else:
		t.eq(PcgWorldDressing.cluster_proxy_for(mesh), null,
			"stock Godot never tries to call missing native engine")
		t.eq(proxy.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size(), 36,
			"stock Godot keeps the original cheap box proxy")
	t.eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX], original_indices,
		"building a GPU proxy never modifies original gameplay/collision geometry")
