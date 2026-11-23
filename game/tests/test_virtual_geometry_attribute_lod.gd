extends RefCounted
## P1 Nanite groundwork: native attribute-weighted mesh decimation is used
## for the real game's scattered props and preserves imported surface channels.
const MeshLOD = preload("res://scripts/client/mesh_lod_preservation.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")


static func _source_mesh() -> ArrayMesh:
	const SIDE := 25
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	for z in SIDE:
		for x in SIDE:
			vertices.append(Vector3(x, sin(float(x) * 0.14) * cos(float(z) * 0.14) * 0.4, z))
			normals.append(Vector3.UP)
			uv.append(Vector2(x, z) / float(SIDE - 1))
			uv2.append(Vector2(x + 1, z + 1) / float(SIDE))
			colors.append(Color(float(x) / SIDE, float(z) / SIDE, 0.45))
			tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	for z in SIDE - 1:
		for x in SIDE - 1:
			var a: int = z * SIDE + x
			indices.append_array(PackedInt32Array([
				a, a + SIDE, a + 1, a + 1, a + SIDE, a + SIDE + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.surface_set_name(0, "painted-scatter")
	var pbr := StandardMaterial3D.new()
	pbr.albedo_color = Color(0.5, 0.8, 0.2)
	pbr.roughness = 0.36
	pbr.metallic = 0.21
	result.surface_set_material(0, pbr)
	result.resource_name = "P1 fidelity ground prop"
	return result


func run(t) -> void:
	t.current = "production scenery takes the native weighted attribute path, not a toy renderer"
	var catalog_source: String = (ModelCatalog as Script).source_code
	var lod_source: String = (MeshLOD as Script).source_code
	t.check(catalog_source.contains("MeshLOD.with_generated_lods(MeshLOD.with_triangle_budget("),
		"actual Albion streamed prop cache uses triangle budgets with distance LOD")
	t.check(lod_source.contains("with_native_attribute_budget(source, max_triangles)"),
		"real scenery triangle budgeting tries native weighted attributes first")
	t.check(lod_source.contains('native.has_method("simplify_surface_arrays")'),
		"stock Godot and old engine builds retain their original importer fallback")
	t.check(lod_source.contains("var generated := ImporterMesh.new()"),
		"older engine fallback remains the original meshoptimizer importer")

	var source: ArrayMesh = _source_mesh()
	var original: Array = source.surface_get_arrays(0)
	var original_indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	t.check(original_indices.size() > 1000,
		"fidelity fixture contains enough triangles for actual decimation")
	if not ClassDB.class_exists("CgameClusterLOD"):
		t.eq(MeshLOD.with_native_attribute_budget(source, 320), source,
			"stock Godot leaves the imported mesh untouched")
		return
	var native: Object = ClassDB.instantiate("CgameClusterLOD")
	if native == null or not native.has_method("simplify_surface_arrays"):
		t.eq(MeshLOD.with_native_attribute_budget(source, 320), source,
			"older Cgame versions fall back to the stock importer")
		return

	t.current = "native meshopt weighted normals UV and non-destructive PBR fidelity"
	var reduced_arrays: Array = native.call("simplify_surface_arrays", original, 320, 0.6, 0.6)
	t.eq(reduced_arrays.size(), Mesh.ARRAY_MAX,
		"native simplification produces full surface arrays, not position-only geometry")
	if reduced_arrays.size() != Mesh.ARRAY_MAX:
		return
	var reduced_indices: PackedInt32Array = reduced_arrays[Mesh.ARRAY_INDEX]
	t.check(reduced_indices.size() >= 3 and reduced_indices.size() <= 320 * 3,
		"weighted simplification meets the requested near-field triangle budget")
	t.check(reduced_indices.size() < original_indices.size(),
		"native simplification really reduces rendered triangles")
	for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
		t.eq(reduced_arrays[key], original[key],
			"authored PBR/tangent/UV2/painted surface stream is preserved exactly")
	t.eq(source.surface_get_arrays(0)[Mesh.ARRAY_INDEX], original_indices,
		"source mesh is never mutated by index-only simplification")

	t.current = "actual Albion MultiMesh prop bake preserves material and source vertex streams"
	var budgeted: Mesh = MeshLOD.with_native_attribute_budget(source, 320)
	t.check(budgeted != source,
		"real native scene optimization adopts the weighted decimated surface")
	if budgeted != source:
		var arrays: Array = budgeted.surface_get_arrays(0)
		var baked_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		t.check(baked_idx.size() <= 320 * 3 and baked_idx.size() < original_indices.size(),
			"actual game mesh uses the native triangle budget")
		for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
				Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			t.eq(arrays[key], original[key], "game mesh retains imported vertex attributes")
		var baked_pbr := budgeted.surface_get_material(0) as StandardMaterial3D
		t.check(baked_pbr == source.surface_get_material(0),
			"real game mesh keeps its original material reference and textures")
		t.near(baked_pbr.roughness, 0.36, 0.00001,
			"scattered prop roughness survives simplification")
		t.eq((budgeted as ArrayMesh).surface_get_name(0), "painted-scatter",
			"imported surface name remains available to tooling")
	var production_budget: Mesh = MeshLOD.with_triangle_budget(source, 320)
	t.check(production_budget != source,
		"the production model-catalog triangle budget uses the new native feature")
	t.eq(MeshLOD.with_triangle_budget(source, 320), production_budget,
		"full game scatter uses its existing once-per-source caching")

	t.current = "bad or unsupported native input returns no partial mesh output"
	t.eq((native.call("simplify_surface_arrays", original, 0, 0.6, 0.6) as Array).size(),
		0, "zero target is rejected without touching source arrays")
	var invalid := original.duplicate(true)
	invalid[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 999999])
	t.eq((native.call("simplify_surface_arrays", invalid, 1, 0.6, 0.6) as Array).size(),
		0, "bad index is rejected atomically")
	t.eq((native.call("simplify_surface_arrays", original, 320, NAN, 0.6) as Array).size(),
		0, "nonfinite attribute penalty is rejected")
